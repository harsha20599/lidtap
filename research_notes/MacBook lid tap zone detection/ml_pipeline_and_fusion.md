# ML Pipeline and Sensor Fusion for Few-Shot Tap-Zone Classification on a Mac (IMU ~800 Hz + 48 kHz audio)

Scope: event detection, stream alignment, features, models for tiny datasets, fusion, false-trigger rejection, context drift, and macOS deployment. Every claim below has a link; anything I could not source is under Gaps. Items under "Inferences" are my engineering recommendations built from the cited findings, not results from the sources.

## Q1. Onset/event detection in audio and IMU, and aligning the two clocks

### Takeaway
Use a cheap, high-recall gate per stream: a high-passed IMU magnitude threshold with a refractory period, and an audio energy or spectral-flux onset. Then confirm with a second-stage classifier that has a "not a tap" output (TapNet's pattern). Both streams can sit on the same `mach_absolute_time` host clock: macimu stamps each IMU HID report with it, and `AVAudioTime.hostTime` uses it too. The residual offset should be measured once with a sharp impulse.

### Cited Findings
- The Apple Silicon MacBook IMU (believed to be a Bosch BMI286) is reached through undocumented IOKit HID (`AppleSPUHIDDevice`, vendor usage page 0xFF00; usage 3 = accel, usage 9 = gyro). The native rate is about 800 Hz. Reports are 22 bytes, with X/Y/Z as int32 little-endian at offsets 6/10/14; dividing by 65536 gives g or deg/s. — [olvvier/apple-silicon-accelerometer](https://github.com/olvvier/apple-silicon-accelerometer)
- macimu: the default callback is about 100 Hz (`decimation=8`), and `decimation=1` gives the full rate. "Each sample carries a hardware timestamp from the HID report (`mach_absolute_time`)", not a Python-side clock. It needs root (`PermissionError` otherwise). It also exposes lid angle (degrees) and ambient light. Its only tested machine is a MacBook Pro M3 Pro on macOS 15.6.1. Known incompatible: Intel Macs, the M1 MacBook Pro (2020), and the Mac Studio M4 Max. `available()` returns True on "MacBook Pro M2+". — [macimu on PyPI](https://pypi.org/project/macimu/)
- macimu ships `peak_detect(values, threshold, min_spacing)` (its impact example uses threshold 1.2), biquad Butterworth filters (example `high_pass(samples, 10.0, 100.0, order=4)`), a Kalman gravity remover (`GravityKalman`), median spike filtering, and rolling RMS. — [macimu on PyPI](https://pypi.org/project/macimu/); [olvvier repo](https://github.com/olvvier/apple-silicon-accelerometer)
- The `spank` slap detector on the same IMU lists its detectors as "STA/LTA, CUSUM, kurtosis, peak/MAD". The README gives no window lengths or thresholds. Its defaults: min amplitude 0.05 g, cooldown 750 ms, polling 10 ms, sample batch 200. `--fast` uses 0.18, 350 ms, 4 ms, and 320. — [taigrr/spank](https://github.com/taigrr/spank)
- TapNet (CHI 2021, phone IMU at about 416 Hz): a heuristic gate on accel z-axis peaks is "a necessary (high recall) but not sufficient (low precision) signal" for a tap. Peaks closer than 80 ms are merged into one impulse, and a magnitude threshold sets sensitivity. It keeps a 150 ms buffer and uses a 120 ms feature window (50 samples per channel) aligned on the first major z peak. Most of the latency (about 105 ms) is spent waiting for the full tap signal; inference itself takes 0.56 ms on a phone CPU. — [TapNet (ar5iv)](https://ar5iv.labs.arxiv.org/html/2102.09087)
- Keystroke acoustic attack on a MacBook Pro 16" (2021): keystrokes are isolated by converting audio to FFT energy (summed across frequencies) and thresholding. Each keystroke segment is a fixed 14,400 samples (0.33 s at 44.1 kHz). For the Zoom data, the threshold was adjusted iteratively until the expected count of presses was found. — [Harrison, Toreini, Mehrnezhad 2023 (arXiv 2308.01074)](https://arxiv.org/html/2308.01074)
- aubio onset methods: `hfc` (default), energy, complex, phase, mkl, kl, `specflux` (Dixon, DAFx-06), and specdiff. Peak-picking threshold defaults to 0.3 (typical range 0.001–0.9; lower values give more onsets). Silence gate defaults to −90 dB (−20 dB keeps only the loudest onsets). `minioi` (minimum inter-onset interval) defaults to 20 ms. Threshold, silence and minioi can be changed while it runs. — [aubioonset man page](https://aubio.org/manpages/latest/aubioonset.1.html); [aubio Rust crate](https://docs.rs/crate/aubio/latest/source/src/onset.rs)
- ALTo (acoustic tap localization with piezo contact mics): a simple amplitude threshold (trigger at 1000, onset index recorded at 500) is fragile because "based on the loudness of the tap, this can vary". Quieter signals at distant sensors skew timing, and the authors propose matching waveform shapes instead. Raising the sample rate from 44.1 kHz to 192 kHz "significantly reduced the variability of the readings". — [ALTo, arXiv 2108.06837](https://ar5iv.labs.arxiv.org/html/2108.06837)
- `AVAudioTime` can represent a moment as host time (based on `mach_absolute_time()`), as a sample time, or both, and provides `seconds(forHostTime:)` and `hostTime(forSeconds:)` helpers. — [Apple AVAudioTime docs](https://developer.apple.com/documentation/avfaudio/avaudiotime)
- Developer reports (not official docs): `sampleTime` differs between AVAudioEngine input and output nodes, so `hostTime` was used to find the offset, and node latency properties often read 0.0. One older Core Audio list post reported the AudioTimeStamp host time running at "double clock rate" relative to `mach_absolute_time` in some runs. — [Apple Dev Forums 68611](https://developer.apple.com/forums/thread/68611); [Stack Overflow mirror](https://dev.library.kiwix.org/content/stackoverflow_en_nopic_2021-08/questions/65600996/avaudioengine-reconcile-sync-input-output-timestamps-on-macos-ios); [coreaudio-api 2008](https://lists.apple.com/archives/coreaudio-api/2008/Oct/msg00263.html)

### Inferences
- Recommended detector:
  1. IMU: high-pass at about 10–20 Hz (or Kalman gravity removal), then take |a_hp| plus |gyro|. Run STA/LTA (for example STA 5 ms / LTA 500 ms, ratio of about 3–5) or a MAD-based z-score. Merge peaks within about 80 ms (TapNet) and apply a refractory period of about 150–300 ms.
  2. Audio: compute 256–512-sample frame energy or spectral flux at 48 kHz (about 5–10 ms) with an adaptive median threshold.
  3. Declare a candidate when either stream fires, then look for the other within ±20–30 ms.
  4. Snip windows anchored on the onset: about 100–150 ms of IMU (80–120 samples) and about 100–250 ms of audio.
- The detector should be causal and streaming. librosa's `onset_detect` is offline (it peak-picks over a whole envelope), so use it only for prototyping and labelling. For real time, use aubio, a hand-rolled spectral flux in vDSP, or Essentia's streaming mode.
- Alignment procedure:
  1. Stamp IMU samples with the HID `mach_absolute_time`.
  2. Stamp audio buffers with `AVAudioTime.hostTime` plus the sample offset ÷ the sample rate.
  3. Run a 10–20-tap calibration of sharp knocks and estimate the constant offset by cross-correlating the IMU high-pass magnitude envelope against the audio envelope (both resampled to about 1 kHz).
  4. Store the median offset and re-estimate it occasionally from confident taps.
  At 800 Hz the IMU's resolution is 1.25 ms, so millisecond-level alignment is enough for feature windowing. Do not attempt cross-modal TDOA.

### Gaps
- I found no published STA/LTA or CUSUM parameters for the MacBook IMU. spank's README names the methods but does not give parameters, and I did not read its source.
- I could not verify how much HID report batching or jitter the SPU adds, or the true end-to-end latency from IMU report to user space.
- The librosa onset docs URL returned 404, so I did not verify its parameter defaults.
- No source confirms whether `AVAudioEngine` input timestamps on built-in MacBook mics already compensate for hardware or DSP latency.

## Q2. Features: raw waveforms vs log-mel/MFCC, spectral, decay, gyro axis ratios, inter-mic phase

### Takeaway
Comparable systems that work with little data use either hand-crafted time and frequency features fed to classic classifiers (TapPrints, Touch & Activate, Taprint) or small log-mel spectrogram "images" fed to CNNs (keystroke attack). TapNet found that first-derivative raw IMU signals work well for CNNs. For a laptop with about 800 Hz IMU and possibly beamformed mics, combine a compact hand-crafted vector (IMU axis peaks and signs, gyro/accel ratios, decay, audio log-mel band energies, centroid) with a raw-window path for later.

### Cited Findings
- TapPrints (MobiSys 2012) inferred tap locations on phones and tablets from accelerometer and gyroscope alone. It reports up to 90% for tap location and up to 80% for English letters. — [TapPrints, ACM DOI 10.1145/2307636.2307666](https://www.springerprofessional.de/doi/10.1145/2307636.2307666)
- A survey describes a tap-inference study (likely TapPrints, but not named in the excerpt) as extracting time- and frequency-domain features and using kNN, multinomial logistic regression, SVM, random forests and bagged decision trees together in an ensemble. — [Survey of personally identifiable sensor data, arXiv 2003.06159](https://arxiv.org/pdf/2003.06159)
- In phone tap inference, the gyroscope performed especially well, sensor fusion showed promise, and accelerometer alone offered less benefit. — [core.ac.uk record](https://core.ac.uk/works/11379913) (search summary; full text not read)
- TapNet input: the first derivative of raw accelerometer and gyroscope signals, concatenated into one channel, plus a device form-factor vector. A 120 ms window is aligned on the first major z peak. — [TapNet](https://ar5iv.labs.arxiv.org/html/2102.09087)
- Keystroke acoustic attack features: 64 mel bands, 1024-sample window, hop 500 (255 for MacBook keystrokes; Table 3 says 225, which conflicts), giving 64×64 images. Augmentation: random time shift of up to ±40%, plus SpecAugment-style masking of 10% of the time and frequency axes (two masks per axis, filled with the mean). — [arXiv 2308.01074](https://arxiv.org/html/2308.01074)
- Touch & Activate (UIST 2013) uses the resonant response of a solid object, taking an FFT of the recorded signal and classifying it with an SVM. A survey attributes 99.6% (five touch gestures) and 86.3% (six hand postures on a toy) to Touch & Activate, possibly from a later paper. — [Tsukuba IPLab](https://www.iplab.cs.tsukuba.ac.jp/en/paper/6151b7ff551fd46e82abdb1b); [Acoustic sensing survey, arXiv 1901.03450](https://arxiv.org/pdf/1901.03450)
- Taprint (MobiCom 2019) uses a wristband motion sensor to capture the vibration of taps on knuckles, using "tapping vibrometry" both to tell tap locations apart and to authenticate the user. It reports 96% keystroke recognition across 128 users. The slides give 95.64% over 12 keys and 113 subjects, so the figures differ between versions. — [Taprint paper](https://island520.github.io/pdf/Taprint-Mobicom%2019.pdf); [slides](https://island520.github.io/slide/Taprint-Mobicom%2019%20slide.pdf)
- ViBand needed a custom kernel to raise a smartwatch accelerometer to 4 kHz, because stock APIs cap at about 100 Hz, in order to capture bio-acoustic signals. — [ViBand, UIST 2016](https://www.robertxiao.ca/research/viband/); [CMU news](https://www.cmu.edu/news/stories/archives/2016/october/smartwatch-capability.html)
- Toffee (laptop prototype) uses acoustic time-difference-of-arrival between microphones to resolve tap bearing on a tabletop, with a mean error of 4.3°. — [Toffee, MobileHCI 2014](https://chrisharrison.net/index.php/Research/Toffee)
- ALTo uses TDOA multilateration with 4 piezo sensors and gets 1.45 cm (x) / 2.72 cm (y) mean error. It needs a per-surface wave-speed calibration (speeds differed by axis: 45,014 vs 37,259 cm/s). — [ALTo](https://ar5iv.labs.arxiv.org/html/2108.06837)
- Apple describes the 13/14/16-inch MacBook Pro mics as a "studio-quality three-mic array" with directional beamforming. — [Apple MacBook Pro tour](https://support.apple.com/guide/macbook-pro/apd2182293a1/2023/mac/13); [MacRumors](https://macrumors.com/2021/10/18/apple-macbook-pros-headphone-jack-high-impedance)

### Inferences
- The IMU is the primary location sensor. With about 800 Hz sampling (Nyquist about 400 Hz), it captures low-frequency chassis and hinge rocking modes, not the kHz structure-borne transient. Lid taps rotate the lid about the hinge and torque the base, so gyro axis signs and ratios (for example ωx:ωy:ωz at peak, and sign of the first gyro lobe) should encode left/right and top/bottom. That fits the TapPrints/core.ac.uk finding that gyro is the strongest phone sensor.
- Recommended per-tap IMU features (6 channels, high-passed, about 100 ms post-onset):
  - per-axis peak value and sign;
  - time-to-peak;
  - |peak| ratios across axes (gyro_x/gyro_y, accel_z/|accel|);
  - signed integral of the first lobe;
  - RMS;
  - energy decay constant (fit log-envelope slope);
  - zero-crossing count;
  - 8–16 FFT band energies (0–400 Hz);
  - lag and coefficient of accel–gyro cross-correlation.
  That gives about 60–100 dimensions. Normalize per tap by total energy so tap strength does not dominate, and keep log-energy as a separate feature.
- Recommended audio features (about 150 ms window):
  - 32–64 log-mel bands averaged over 2–4 time slices;
  - spectral centroid, rolloff and flatness;
  - log-energy and decay time.
  If raw multichannel mic access exists, add GCC-PHAT lag and coherence per mic pair (Toffee/ALTo-style TDOA cues). Lid taps travel through the chassis, so inter-mic lags will be only microseconds to sub-millisecond. Use 48 kHz with upsampled cross-correlation, and treat these as fingerprint features for a classifier, not physical localization (ALTo found wave speed is material- and axis-dependent).
- Keep raw windows (IMU 6×96 at 800 Hz, audio log-mel 64×32) logged from day one, so a small CNN or contrastive encoder can be trained later on the user's accumulated data.

### Gaps
- I could not confirm whether macOS exposes the three built-in MacBook mics as separate raw channels or only as a beamformed or processed mono/stereo stream. This decides whether inter-mic phase features are possible.
- I found no published feature-importance study for laptop-lid taps specifically. The TapPrints and ViBand full texts (feature lists, numeric accuracy) were not retrievable; the ViBand PDF could not be parsed.
- I do not know where the IMU physically sits (base vs lid). macimu does not say.

## Q3. Models for tiny datasets, taps per zone, online learning

### Takeaway
For roughly 5–20 taps per zone, start with standardized hand-crafted features fed to kNN/nearest-centroid, SVM-RBF and random forest, and compare them by leave-one-tap-out validation. Add DTW or cross-correlation template matching as a baseline. Deep models only pay off with large data or pretraining. TapNet's 35-class IMU location F1 was just 0.34–0.54 even with 135K training samples, because of cross-user variation. Keystroke CNNs reached 95% with about 20 examples per class but used heavy augmentation and 1,100 epochs. Use per-user and per-device calibration plus continual updating from user corrections (Core ML updatable kNN, or river).

### Cited Findings
- Keystroke attack: 36 keys × 25 presses each, 180 test samples (so roughly 20 training presses per key). CoAtNet (2 depth-wise conv layers plus 2 relative-attention layers, average pooling, then a fully connected layer). Adam, batch 16, 1,100 epochs, max LR 5e-4. Results: 95% top-1 / macro-F1 0.95 from a phone at 17 cm, and 93% / F1 0.94 over Zoom using the MacBook's built-in mic array. — [arXiv 2308.01074](https://arxiv.org/html/2308.01074)
- TapNet results (trained on one person, tested on 31; 35-class 5×7 grid location):

  | Task | SVM | TinyCNN | TapNet |
  |---|---|---|---|
  | Location F1 | 0.13 | 0.03 | 0.34 (0.42 in Table 5) |
  | Direction F1 | 0.55 | 0.47 | 0.85 |

  Fine-tuning leave-one-participant-out raised location F1 to 0.54 and direction F1 to 0.92. Ablation models were 9K–163K parameters. Dataset: more than 135K training and 38K test samples from 32 participants. — [TapNet](https://ar5iv.labs.arxiv.org/html/2102.09087)
- TapPrints: up to 90% tap location and 80% letters with an ensemble of classic classifiers on phone IMU. — [TapPrints](https://www.springerprofessional.de/doi/10.1145/2307636.2307666); [survey 2003.06159](https://arxiv.org/pdf/2003.06159)
- A field study (27 participants, 3 iPhone models, about 25,000 taps) found tap-location inference still possible in the wild, but about 20% worse than in the lab. — [unpaywall record 10.1007/978-3-030-50309-3_43](https://unpaywall.org/10.1007%2F978-3-030-50309-3_43) (from search summary; numbers not verified in full text)
- Mic plus motion tap-location study (MDPI Applied Sciences 2021): a random forest predicted touch location "with up to 86% accuracy in a realistic scenario". — [MDPI Appl. Sci. 11(11):4834](https://www.mdpi.com/2076-3417/11/11/4834) (page returned 403; claim from search snippet)
- Prototypical networks are proposed for registering custom IMU gestures from few samples, since "a learning algorithm based on a large amount of data is incompatible" with newly registered gestures (patent, not peer-reviewed). A 2024 JNER paper uses prototypical networks for one-shot adaptation of a subject-independent IMU gesture model. — [USPTO few-shot gesture patent](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/12205407); [JNER 2024](https://link.springer.com/10.1186/s12984-024-01398-7)
- MiniRocket uses a small fixed set of almost deterministic convolution kernels and trains a linear classifier on the transformed features. In tsai it is not a deep model and needs sktime. InceptionTime is an ensemble of 5 Inception CNNs. — [MiniRocket arXiv 2012.08791](https://pdf.arxiv.org/pdf/2012.08791); [tsai GitHub](https://github.com/timeseriesAI/tsai)
- Core ML can personalize models on-device with `MLUpdateTask`. Updatable types are neural networks, pipelines and nearest-neighbor classifiers. Core ML k-NN is classification-only with no fixed class cap. The recommended pattern is k-NN on top of a neural feature extractor. Updatable models are made with coremltools (spec v4+), not Create ML. — [Core ML 3 on-device training](https://iosdevie.substack.com/p/coreml3-on-device-training); [coremltools updatable model examples](https://cymbalrush.github.io/coremltools/docs-guides/_sources/source/updatable-model-examples.rst); [Kodeco tutorial](https://www.kodeco.com/7960296-core-ml-and-vision-tutorial-on-device-training-on-ios?page=2)
- River (the Creme and scikit-multiflow merger) offers streaming `learn_one`/`predict_one`/`predict_proba_one` APIs and includes (approximate) nearest neighbors. — [River paper, arXiv 2012.04740](https://ar5iv.labs.arxiv.org/html/2012.04740)

### Inferences
- Recommended progression:
  - **v0:** z-scored hand-crafted features fed to kNN (k=3, distance-weighted) and nearest-centroid with a per-class Mahalanobis or cosine distance. This is a prototypical network without the learned embedding.
  - **v1:** SVM-RBF and random forest (scikit-learn), chosen by leave-one-tap-out CV. Also run a DTW or max-normalized cross-correlation template matcher on the 6-axis IMU snippet as a strong low-data baseline.
  - **v2:** once a few hundred to a few thousand self-collected taps exist across sessions, a small 1D-CNN (about 10–50K params, TapNet-like) on derivative IMU plus log-mel. Alternatively, a contrastive encoder pretrained on unlabeled detected taps and augmentations (time shift ±10–20 ms, gain jitter, SpecAugment masks, IMU axis noise), with a linear or prototype probe per user.
- Taps per zone: no laptop-specific source exists. The comparable evidence (about 20 per class giving 95% for 36 acoustic keystroke classes with a CNN, and up to 90% for phone IMU taps with classic ensembles) suggests budgeting 10–20 taps per zone for 3×3 (90–180 taps, about 2–3 minutes) and 15–25 for 4×4. Report learning curves at 3/5/10/20 shots on your own data. Coarse grids should reach about 90% sooner because adjacent-zone confusion dominates.
- Continual learning: append each user-confirmed or corrected tap to the kNN memory, capped per class (for example the 50 most recent, or herding/reservoir selection). Recompute centroids, and drop exemplars older than N days or from stale contexts. This is cheap, interpretable and reversible.

### Gaps
- I found no published learning curve (accuracy vs. taps per zone) for laptop-chassis or lid taps. The 10–20 per zone figure is an extrapolation.
- I found no paper directly applying prototypical networks or contrastive pretraining to tap localization with built-in sensors.
- I did not confirm the current (2025–2026) status of Core ML `MLUpdateTask` on macOS; the sources are from the Core ML 3 era. I also did not verify River's kNN class name (`river.neighbors`).

## Q4. Sensor fusion (early vs late) and evidence that IMU + audio helps

### Takeaway
The evidence for fusion is suggestive, not conclusive. Within motion sensors, fusing gyro and accel helps. A mic plus IMU random forest reached 86%. There is no clean head-to-head showing audio+IMU beats the best IMU-only setup for tap location. With a tiny dataset, start with feature-level early fusion (concatenate the z-scored IMU and audio vectors into one kNN/SVM) and compare it with late fusion (per-modality classifiers combined by log-probability sum). Keep both, because late fusion degrades gracefully when one modality is corrupted, for example by music or speech.

### Cited Findings
- Phone side channels: the gyroscope performed best, fusion of sensor readings showed potential, and accelerometer alone was less useful. — [core.ac.uk record](https://core.ac.uk/works/11379913)
- Microphone plus accelerometer and gyroscope tap-location inference: a random forest reached up to 86% "in a realistic scenario". The paper compares acoustic and movement features, but the snippet did not give a per-modality breakdown. — [MDPI Appl. Sci. 2021](https://www.mdpi.com/2076-3417/11/11/4834)
- Built-in-sensor acoustic location (Toffee): 4.3° mean bearing error on a laptop prototype from mic TDOA, relying on gravity to couple the device to the surface acoustically. — [Toffee](https://www.figlab.com/research/2014/toffee)
- Acustico (FRL/Dartmouth) uses wrist-based acoustic TDOA for surface tap detection and 2D localization. — [Acustico](https://research.fb.com/publications/acustico-surface-tap-detection-and-localization-using-wrist-based-acoustic-tdoa-sensing/)
- TapNet's multi-task CNN (shared conv trunk, task heads) beat single-task variants on direction (F1 0.85 vs 0.82 SISO) and location (0.34 vs 0.30). This supports shared representations across related outputs (event or not, location, strength). — [TapNet](https://ar5iv.labs.arxiv.org/html/2102.09087)

### Inferences
- Recommended fusion:
  1. Early fusion of per-modality z-scored feature blocks, with block weights tuned by CV (for example scale the audio block by α ∈ {0.5, 1, 2}).
  2. In parallel, late fusion: p(zone) ∝ p_imu^w · p_audio^(1−w), with w chosen per context.
  3. Gate the audio contribution by an ambient-noise estimate. If the pre-onset audio RMS or spectral flatness indicates speech or music, rely on IMU only.
- Audio is likely more useful for event validation (sharp broadband click vs. thud vs. speech) and for tap-vs-bump discrimination than for zone discrimination, unless raw multichannel mic phase is available.

### Gaps
- I found no study measuring the accuracy gain from adding audio to IMU for tap location on a laptop, or with matched data across modalities.
- The MDPI paper's per-modality numbers could not be read (HTTP 403).

## Q5. False-trigger rejection: typing, trackpad, bumps, speech or music, lid motion

### Takeaway
Use layered rejection:
1. Hard gates from OS input events: suppress candidates within about 150–300 ms of a key or trackpad event from a listen-only `CGEventTap`, which needs Input Monitoring.
2. A lid-angle gate from the SPU lid sensor: suppress when the angle is changing.
3. An explicit "non-tap" class trained on recorded negatives (TapNet trained on 26K non-tap samples).
4. Open-set distance or confidence thresholds on the kNN/prototype output.
5. Optionally, a double-tap confirmation for high-consequence actions.

### Cited Findings
- TapNet trains its event head on 26,060 non-tap samples (grasping, rubbing the case, tap release, knocking the surface, shaking in a pocket or bag) and pre-filters obvious non-taps with the accel peak gate. Event F1 was 0.87–0.92. — [TapNet](https://ar5iv.labs.arxiv.org/html/2102.09087)
- A listen-only `CGEventTap` relies on the Input Monitoring privilege, which is available to sandboxed apps. NSEvent global monitors require Accessibility (Apple DTS guidance). Access is checked and requested with `CGPreflightListenEventAccess` / `CGRequestListenEventAccess`. Taps can fail silently without permission. — [Apple Dev Forums 707680](https://developer.apple.com/forums/thread/707680); [keytap crate source](https://docs.rs/crate/keytap/0.3.0/source/src/platform/macos/tap.rs); [Apple Dev Forums 811443](https://developer.apple.com/forums/thread/811443)
- NSEvent monitors cannot receive Secure Keyboard Entry events. — [slide deck on macOS event monitoring](https://docs.google.com/presentation/d/1nEaiPUduh1vjks0rDVRTcJaEULbSWWh1tVdG2HF_XSU/htmlpresent)
- macimu exposes the lid angle sensor (degrees) alongside accel and gyro. — [macimu](https://pypi.org/project/macimu/)
- The keystroke paper shows MacBook keystrokes are acoustically distinct and classifiable from built-in mics (93% over Zoom). Typing is therefore a strong, structured confound that a model can learn to reject, and also one the OS can gate on. — [arXiv 2308.01074](https://arxiv.org/html/2308.01074)
- OpenMax (CVPR 2016) fits a per-class Weibull distribution to distances between correctly classified activations and class mean vectors. It rejects as unknown if the unknown class wins or the top probability is below a threshold. Thresholded softmax alone improves open-set recognition "somewhat" but softmax remains overconfident. — [Bendale & Boult, arXiv 1511.06233](https://arxiv.org/abs/1511.06233); [CVF open access](https://openaccess.thecvf.com/content_cvpr_2016/html/Bendale_Towards_Open_Set_CVPR_2016_paper.html)
- spank uses a cooldown (350–750 ms) plus an amplitude floor as its only false-trigger controls. — [spank](https://github.com/taigrr/spank)
- Ubicoustics reached about 80% in-the-wild accuracy for acoustic activity recognition. Harrison reportedly said 90–95% would be needed for deployment, which is a useful bar for a reject classifier. — [Ubicoustics (FIGLAB)](https://www.figlab.com/research/2018/ubicoustics); [The Register](https://www.theregister.com/2018/10/15/alexa_sound_recognition)

### Inferences
- Gates:
  - Suppress for about 200 ms after any `keyDown`/`keyUp`/`flagsChanged`, `leftMouseDown`/`Up`, scroll or trackpad pressure event.
  - Suppress for about 500 ms after |d(lid angle)/dt| exceeds about 2°/s.
  - Suppress while the accelerometer low-frequency (<5 Hz) energy is elevated, which indicates laptop movement or lap use.
- Learned reject:
  - Collect 1–2 minutes of negatives per user: typing, trackpad clicks, desk knocks, picking up, speech and music playback, and closing or opening the lid.
  - Train a binary tap/non-tap model (random forest or logistic regression) before the zone classifier.
  - Add an open-set check: reject if the nearest-prototype distance exceeds the 95th–99th percentile of in-class calibration distances (a simple EVT/OpenMax analogue), or if top-1 minus top-2 probability is under a margin.
- Self-generated audio: when the Mac is playing audio, consider using voice-processing AEC, or rely on the IMU only. The speaker's own output can create vibration and audio onsets.
- Double-tap confirmation (two taps in the same zone within 150–500 ms) sharply cuts the false-positive rate at a latency cost. Make it optional per action.

### Gaps
- I found no published false-positive rates for laptop-tap systems under typing or desk bumps.
- I did not verify whether trackpad Force Touch clicks produce IMU signatures distinct from lid taps. The OS event gate is assumed to cover them.

## Q6. Context changes: lid angle, desk vs lap, AC adapter, temperature

### Takeaway
Expect significant domain shift. Lab-to-field tap inference lost about 20%, and TapNet cross-user location F1 rose from 0.34–0.42 to 0.54 only after adaptation. The practical answer is per-context profiles keyed on measurable state (lid-angle bin, a stability or lap indicator from low-frequency accel, power state), with a quick 1–2-tap-per-zone re-anchoring and continual exemplar updating. Heavy domain-adaptation machinery is not needed.

### Cited Findings
- Field vs lab tap inference: about a 20% performance reduction. — [unpaywall 10.1007/978-3-030-50309-3_43](https://unpaywall.org/10.1007%2F978-3-030-50309-3_43) (search summary)
- TapNet cross-user location F1 was 0.34–0.42 without adaptation and 0.54 with leave-one-out fine-tuning. Direction rose from 0.85 to 0.92. TapNet also feeds a device form-factor vector so one model can serve multiple phones. — [TapNet](https://ar5iv.labs.arxiv.org/html/2102.09087)
- Toffee relies on gravity coupling the device to a hard tabletop, so its acoustic propagation depends on the support surface. — [Toffee](https://chrisharrison.net/index.php/Research/Toffee)
- ALTo found wave speed varies with material and axis, and it biased errors in part of the board. Per-surface calibration was required. — [ALTo](https://ar5iv.labs.arxiv.org/html/2108.06837)
- The lid angle is directly readable from the SPU sensor. — [macimu](https://pypi.org/project/macimu/)

### Inferences
- Context key: (lid-angle bin of about 10–15°, surface = desk/lap/stand inferred from low-frequency accel variance and gravity tilt, power = AC/battery from IOKit power sources). Store separate exemplar sets per key and fall back to the nearest key.
- Add lid angle as a feature, or condition on it, as TapNet did with device form factor. Train one model with an angle input rather than many models, once enough data exists.
- Re-anchoring: when confidence drops (rising reject rate or falling margin), prompt for a 1-tap-per-zone recalibration. Shift class prototypes by the mean feature delta (a feature-mean alignment, CORAL-lite) instead of retraining.
- Temperature and AC adapter effects are probably secondary (cable strain changes damping; fan noise affects audio). Track them as metadata and check empirically.

### Gaps
- I found no source that quantifies lid-angle, lap-vs-desk, AC-cable or temperature effects on laptop tap classification. All of this is untested.

## Q7. On-device deployment on macOS and useful toolkits

### Takeaway
Prototype in Python (macimu for IMU, sounddevice or PyAudio for audio, numpy/scipy/scikit-learn, optionally tsai/sktime MiniRocket). Ship as a Swift app or daemon:
- IOKit HID for the IMU (requires root, so a privileged helper or LaunchDaemon);
- AVAudioEngine for audio;
- vDSP/Accelerate for filtering, FFT and mel;
- a hand-written kNN/centroid in Swift, or Core ML (updatable kNN or a small CNN converted by coremltools).

The latency budget is dominated by waiting for the tap window (about 100–150 ms). Inference is sub-millisecond.

### Cited Findings
- TapNet inference costs 0.56 ms on a phone CPU (about 9 ms for a simplified DSP model). About 105 ms of end-to-end delay is spent waiting for the full tap signal. — [TapNet](https://ar5iv.labs.arxiv.org/html/2102.09087)
- IMU access needs root. spank installs as a root LaunchDaemon (`/Library/LaunchDaemons`, no `UserName`). taigrr's Go port runs a root `sensord` daemon with a client. — [spank](https://github.com/taigrr/spank); [macimu](https://pypi.org/project/macimu/); [taigrr/apple-silicon-accelerometer](https://gh.r-mj.com/taigrr/apple-silicon-accelerometer)
- The undocumented AppleSPU HID path is experimental and "may break on future macOS updates". — [macimu](https://pypi.org/project/macimu/)
- Core ML `MLUpdateTask` updates kNN, neural-network and pipeline models on device. Updatable models are authored with coremltools; Create ML does not produce them. — [Core ML on-device training](https://iosdevie.substack.com/p/coreml3-on-device-training); [coremltools updatable examples](https://cymbalrush.github.io/coremltools/docs-guides/_sources/source/updatable-model-examples.rst)
- Create ML / Turi Create activity classifiers use a "prediction window" (samples per label) at a fixed sample rate. For example, a 50-sample window at 50 Hz gives one prediction per second, which suits continuous activities rather than event-anchored taps. — [Turi Create activity classifier advanced usage](https://apple.github.io/turicreate/docs/userguide/activity_classifier/advanced-usage.html); [Create ML activity walkthrough](https://medium.com/@tyler.hutcherson/activity-classification-with-create-ml-coreml3-and-skafos-part-1-8f130b5701f6)
- `SNClassifySoundRequest` exposes `windowDuration`, `overlapFactor` and `windowDurationConstraint`. Apple recommends the Audio Feature Print extractor for custom models because it allows variable window control. A community model used a 0.975 s window with 75% overlap. — [SNClassifySoundRequest docs](https://developer.apple.com/documentation/soundanalysis/snclassifysoundrequest); [WWDC21 session 10036](https://developer.apple.com/videos/play/wwdc2021/10036/); [Medium example](https://medium.com/@aversanamichele/classifying-sounds-with-the-soundanalysis-framework-and-custom-createml-models-in-swift-bd59fa693d8e)
- tsai (PyTorch/fastai) includes InceptionTime and MiniRocket; MiniRocket needs sktime. — [tsai](https://github.com/timeseriesAI/tsai)
- River provides streaming `learn_one`/`predict_one` APIs for online models. — [River](https://ar5iv.labs.arxiv.org/html/2012.04740)
- aubio offers real-time onset detection with adjustable threshold, silence and minioi. — [aubio](https://aubio.org/manpages/latest/aubioonset.1.html)

### Inferences
- Architecture:
  - **Root helper:** reads the IMU via IOHID at the full 800 Hz (decimation 1) and streams timestamped samples over XPC or a Unix socket to a user agent.
  - **User agent:** handles AVAudioEngine input (48 kHz; 256–512-frame buffers, about 5–10 ms), the `CGEventTap` keyboard and mouse gate, ring buffers, the onset detector, feature extraction (vDSP biquads, FFT, mel filterbank), the classifier and the action dispatch.
- Latency target: onset + 120 ms window + under 5 ms of compute + action, so roughly 130–170 ms from tap to action. That is acceptable for discrete commands.
- Avoid Create ML Activity and Sound classifiers as the main zone model. Their fixed-window, continuous-classification design and roughly 1 s audio windows do not suit 100 ms event-anchored snippets, and they are not updatable. They could be useful for an auxiliary "is this a tap vs speech/music/typing" audio classifier.
- Prefer a pure-Swift kNN or centroid model, which is trivially updatable and needs no MLUpdateTask, until a CNN embedding is warranted. Then export the embedding with coremltools and keep the kNN head in Swift. ONNX Runtime (CoreML EP) is an alternative if training in PyTorch, but adds a dependency.
- Python toolkit for R&D: macimu, sounddevice, numpy/scipy, librosa (offline analysis and labelling), aubio or essentia (streaming onset), scikit-learn (kNN/SVM/RF, CV), tsfresh (broad automatic feature screening), sktime/tsai (MiniRocket baseline), river (online kNN and drift detectors such as ADWIN). Edge Impulse is optional for quick DSP-block exploration, but it targets MCUs and is not needed on a Mac.

### Gaps
- I did not verify the current Core ML updatable-model support on macOS 26/27, or whether Apple has deprecated `MLUpdateTask`.
- I did not find benchmarks for AVAudioEngine input latency on built-in MacBook mics, or ONNX Runtime vs Core ML latency for models this tiny. I did not research tsfresh, essentia streaming, or Edge Impulse specifics in depth.
- The legal and permission implications of shipping a root IOKit helper (notarization, SMAppService) were not researched.
