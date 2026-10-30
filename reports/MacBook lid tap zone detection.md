# Turn hinge torque into lid buttons

The best way to get zone taps on a MacBook lid without extra hardware is to use the **hidden Bosch 6-axis IMU in the base as the main sensor, and to lean on its gyroscope in particular**. A tap on the lid twists the machine about the hinge. Typing, trackpad clicks and desk bumps mostly shove it sideways instead. A calibrated, per-machine nearest-prototype classifier can turn the sign and ratios of that twist into zones. The built-in microphone is a useful secondary input, for confirming a tap and adding a spectral fingerprint. The lid-angle sensor and macOS input events act as gates. Active ultrasound and the camera are optional research add-ons, not the core of the design. On your machine (MacBook Air 13" M3, Mac15,12, macOS 27.0.1), a first-hand probe read the IMU at **about 794 Hz without root**, gated only by the Input Monitoring permission. The lid-angle sensor also opened and read 132°. The hardware path is therefore already proven on the target device. What nobody has demonstrated publicly is *localizing* taps on a MacBook lid. The closest evidence is phone research: TapPrints inferred tap location from a phone's IMU with up to 90% accuracy ([TapPrints](https://www.springerprofessional.de/doi/10.1145/2307636.2307666)). That makes a coarse grid (left/right, 2×2 or 2×3) a realistic first target. A true 3×3 is a stretch goal that has to earn its place through measured learning curves. Every accuracy figure below for a MacBook lid is an extrapolation until you record labeled taps. Apple's new touchscreen OLED MacBook Pro, announced 2026-10-28, means this approach is for the large installed base of non-touch Macs, used as "tap hotkeys", not as a touchscreen replacement ([CNBC](https://www.cnbc.com/2026/10/28/apple-mac-touchscreen-launch.html)).

## The base gyroscope already separates lid strikes from everything else

Apple Silicon laptops from the M2 generation onward, plus the M1 Pro/Max MacBook Pros, contain a Bosch Sensortec 6-axis accelerometer and gyroscope. iFixit lists it among the logic-board components, which puts it **in the base, not the lid** ([iFixit M2 Air Chip ID](https://www.ifixit.com/Guide/Macbook+Air+13-Inch+Liquid+Retina+2022+Chip+ID/151816); [yamete](https://github.com/chipcolate/yamete)). It is reached through undocumented IOKit HID. The steps are:

1. Wake the `AppleSPUHIDDriver` services by setting `SensorPropertyReportingState=1`, `SensorPropertyPowerState=1` and `ReportInterval=1000` µs. This must happen before opening the devices, because setting the same keys on the device is silently ignored.
2. Open the `AppleSPUHIDDevice` entries with usage page 0xFF00, usage 3 (accelerometer) or 9 (gyroscope), and a 22-byte report size.
3. Parse X, Y and Z as int32 values at byte offsets 6, 10 and 14, divided by 65536 to get g or °/s ([yamete](https://github.com/chipcolate/yamete); [olvvier/apple-silicon-accelerometer](https://github.com/olvvier/apple-silicon-accelerometer)).

olvvier, spank and their derivatives insist on sudo, but that is their own `geteuid()` check. macOS itself gates access only through the **Input Monitoring** TCC grant ([yamete](https://github.com/chipcolate/yamete); [HN discussion](https://news.ycombinator.com/item?id=47084000)).

The local probe on your M3 Air (first-hand measurement, no URL) confirmed this with no root:

- **Rate:** accelerometer and gyroscope both delivered 793.9–794.0 Hz with zero dropped reports.
- **Gyroscope:** values moved in steps of 0.061 °/s, consistent with a 16-bit ±2000 °/s part. Idle standard deviation per axis was 0.2–1.5 °/s.
- **Accelerometer:** consecutive samples differed by only about 0.00015 g, against an overall standard deviation of about 0.01 g. This suggests the accelerometer stream is heavily low-pass filtered inside the sensor hub, so its high-frequency tap content may be smeared. The gyroscope looks far less filtered.
- **Lid angle:** the lid-angle device (usage page 0x20, usage 0x8A) opened and returned 132°. That confirms the sensor is present on the M3 Air, which LidAngleSensor's compatibility table had left unconfirmed ([LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor)).

The probe script is at `tools/imu_probe.py`. It is a ready starting point for recording labeled taps.

The most useful prior art is **yamete**, a Rust slap detector built on this IMU. Its main finding is physical. Hitting the lid applies torque about the hinge, while a knock through the desk mostly translates the machine. In yamete's data, "a desk bump peaks at 0.73 g where a hard slap is 0.52 g," yet the rotation runs the other way: about 15 °/s for the bump versus about 48 °/s for the slap. **Every negative example stayed below 14.6 °/s, while hard slaps reached 16–81 °/s** ([yamete](https://github.com/chipcolate/yamete)). yamete's gate accepts a hit when the ratio of gyro peak to accel peak is at least 175 (°/s)/g, or when the gyro peak is at least 15 °/s. At its default sensitivity it caught 35 of 40 slaps with zero false positives, and typing stayed silent. Raising sensitivity to catch 40 of 40 cost 18 false positives. yamete also reports that published thresholds sit below the real idle noise floor, and recommends per-machine idle calibration ([yamete](https://github.com/chipcolate/yamete)). Streaming both sensors at about 805 Hz costs **about 3.15% of one core**, and the detection logic adds only about 0.35% ([yamete](https://github.com/chipcolate/yamete)).

Two caveats shape everything that follows. First, yamete's corpus is slaps from 0.04 g to 0.62 g. A light fingertip tap probably sits at or below its 0.04 g "micro" tier, and **nobody has published whether fingertip taps clear the gyro's idle noise**. Second, no project attempts localization. The case that zones are recoverable is a physics inference, not a measurement. A tap at height *h* above the hinge produces a pitch impulse roughly proportional to *h*, which sets the top-versus-bottom signal. A tap at lateral offset *x* produces a twist about the lid normal whose sign flips between left and right. Because the accelerometer roughly measures the linear impulse (tap force) and the gyroscope measures the torque, the gyro/accel ratio acts as a force-normalized lever arm. That is the same quantity yamete uses to reject desk bumps, and here it would also encode tap height. One implication is that taps near the hinge produce little torque. **The bottom row of any grid will be the weakest**, and it is also the region (the bezel over hollow space and flex cables) that Apple community guidance says not to press ([Apple Community](https://discussions.apple.com/thread/254712427)).

The phone side-channel literature supports the general idea that a device's own IMU can tell where it was tapped. TapPrints reached up to 90% (phones) and 80% (tablet) from accelerometer plus gyroscope ([TapPrints](https://www.springerprofessional.de/doi/10.1145/2307636.2307666)). A later benchmark found the **gyroscope to be the best single sensor** for keystroke inference ([sensor benchmark](https://portal.arid.my/27/Publications/Details/124)). Field data costs roughly 20 points relative to the lab ([field study](https://unpaywall.org/10.1007%2F978-3-030-50309-3_43)). TapNet is the cautionary counterpoint. Even with more than 135K training samples, its cross-user 35-class grid location F1 was only 0.34–0.42, rising to 0.54 after adaptation ([TapNet](https://ar5iv.labs.arxiv.org/html/2102.09087)). Fine grids across users fail; coarse grids calibrated to one person and one machine are the regime where IMU tap location works.

## Microphones and the camera add confirmation, not direction

The built-in microphone is the strongest secondary channel, but not for the reason the literature on time-difference-of-arrival (TDOA) might suggest. TDOA tap localizers rely on separate sensors spaced tens of centimetres apart and on high sample rates. ALTo used four piezos 26 cm from the origin and found that moving from 44.1 kHz to 192 kHz "significantly reduced the variability"; even then its mean error was 1.45–2.72 cm ([ALTo](https://ar5iv.labs.arxiv.org/html/2108.06837)). On your Mac, a CoreAudio query showed the "three-mic array with directional beamforming" ([Apple specs](https://support.apple.com/en-us/118552)) exposed as **a single, already-beamformed input channel** at 44.1, 48, 88.2 or 96 kHz (local CoreAudio query, no URL). With no per-capsule access, inter-mic phase and TDOA features are simply unavailable.

What remains is the **location template matching** principle: a reverberant plate gives each impact point a near-unique impulse response, so a single sensor can classify pre-recorded locations by cross-correlation ([LTM study](https://koreascience.kr/article/CFKO201431749163690.pdf); [Time reversal interactive objects](https://www.researchgate.net/publication/252367235_Time_reversal_interactive_objects)). Elo's Acoustic Pulse Recognition touchscreens shipped commercially on exactly this lookup-table idea ([Elo](https://elosupport.elotouch.com/hc/en-us/articles/31650748698903-How-does-APR-technology-work)). Laptop keystroke attacks show audio can tell apart closely spaced positions on a MacBook chassis: **95% per key over 36 keys** recorded by a phone at 17 cm, and 93% over a Zoom call ([Harrison et al. 2023](https://arxiv.org/abs/2308.01074v1)). That evidence comes from keys that strike consistently, recorded largely by an external mic. For finger taps on a lid picked up by the internal mic, it is promising but unverified.

Knocker is the best fusion precedent. It identified objects by knocking with a phone and fusing mic, accelerometer and gyroscope, reaching 98% in the lab, **83% in a café or roadside**, and 92% across 23 objects with only 20 training knocks each ([Knocker](https://nmsl.kaist.ac.kr/projects/knocker)). The lesson is that audio adds detail but brings ambient-noise fragility, and the IMU is the noise-immune anchor.

Using the mic also has real costs. The orange mic indicator stays lit whenever capture runs, and macOS gives no way to hide it ([Apple Control Center help](https://support.apple.com/en-au/guide/mac-help/mchl50f94f8f)). An open CoreAudio stream also costs about 4.2% of a core even when silent ([yamete](https://github.com/chipcolate/yamete)). The mic should therefore stay optional, and be judged by whether it measurably improves the IMU-only classifier.

**Active ultrasound is the weakest bet among the acoustic options.** In this approach the speakers emit an inaudible probe and the mic watches for changes. Published contact-sensing successes all have speaker, mic and touched surface in one rigid body, or use transducers glued to the object:

- **Touch & Activate:** 99.6% on five gestures with a contact speaker and piezo ([Tsukuba IPLab](https://www.iplab.cs.tsukuba.ac.jp/en/paper/6151b7ff551fd46e82abdb1b)).
- **ForcePhone:** pressure sensing through a phone body above 18 kHz ([ForcePhone](https://rtcl.eecs.umich.edu/rtclweb/assets/publications/2016/paper-mobisys-final_refined_by_apple.pdf)).
- **VSkin:** 99.65% tap detection on phone surfaces ([VSkin](https://samsonsjarkal.github.io/KeSun/files/mobicom18_vskin.pdf)).

A MacBook lid connects to the base speakers and mic only through a compliant hinge. Laptop speakers deliver usable energy only in about 18–19.5 kHz, with steep attenuation above 21 kHz ([SmartAttack](https://arxiv.org/pdf/2506.08866)). Apple's voice processing must be disabled, because its echo cancellation would subtract the probe signal ([Apple AVAudioIONode](https://developer.apple.com/documentation/avfaudio/avaudioionode.md)). Laptop ultrasound demos to date sense in-air Doppler gestures, not contact: SoundWave in 2012 and a 2026 MacBook "sonar scroller" ([SoundWave](https://people.ece.cornell.edu/land/courses/ece4760/FinalProjects/f2012/alt53_lw354/alt53_lw354/files/GuptaSoundWaveCHI2012.pdf); [runtimewire](https://runtimewire.com/article/openai-astra-macbook-sonar-gesture-scroller)). The only laptop chassis-touch proposal found, PalmEcho, is an unevaluated draft ([PalmEcho](https://guccigrandfather.pages.dev/palmecho)). Ultrasound's one unique strength is detecting a *held* finger, which produces no impulse. Since you want taps, that strength doesn't apply.

The camera cannot see contact. The FaceTime camera looks out along the screen normal, which is why Project Sistine needed a mirror angled down at the glass ([Anish Athalye](https://anishathalye.com/macbook-touchscreen/)). What it can see is the hand and forearm approaching. Apple Vision's hand-pose request returns 21 landmarks per hand on macOS ([Apple Vision docs](https://developer.apple.com/documentation/vision/detecthumanhandposerequest.md)), so a ring buffer of poses from about 50–150 ms before an IMU-detected tap could supply a left/centre/right prior. That pairing has precedent in a patent ([US9971457](https://patents.google.com/patent/US9971457)) and in SurfaceXR, whose authors say hand tracking alone is too inaccurate to detect contact ([SurfaceXR](https://arxiv.org/pdf/2603.19529)). The green camera light stays on during capture ([Macworld](https://www.macworld.com/article/222599/eye-for-an-eye-researchers-foil-camera-indicator-light-on-some-macbooks.html)), so this is a late, opt-in experiment.

The remaining sensors each fall short:

- **Lid-angle sensor:** reports in **integer degrees** and is polled at 30–120 Hz in the OSS tools ([MacDuo](https://github.com/DhananjayBhosale/MacDuo); [LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor)). It is useless for transients, but valuable as a context key and as a veto when the lid is actually moving.
- **Ambient light sensor:** polled at 1–10 Hz via private APIs ([Chromium](https://chromium.googlesource.com/chromium/src/+/c31119bc5/content/browser/device_sensors/ambient_light_mac.cc)). At most a crude top-centre shadow cue.
- **Trackpad force sensing:** reports only while a finger is in capacitive contact ([TrackWeight](https://github.com/KrishKrosh/TrackWeight)).
- **Wi-Fi channel state information (CSI):** has no macOS extraction path ([WiFinger](https://leehomcs.github.io/HongLi.github.io/papers/WiFinger.pdf)).
- **The display panel:** a non-touch panel has no digitizer and exposes no electrical telemetry.

| Channel | Role in the design | Evidence strength | Cost or risk |
|---|---|---|---|
| Base IMU gyroscope (about 794 Hz) | Primary detector and zone features | Measured on your Mac; yamete's slap data | Undocumented API; fingertip SNR unmeasured |
| Base IMU accelerometer | Force normalization, bump rejection | Measured; looks low-pass filtered | Bandwidth limited |
| Built-in mic, passive (1 channel) | Tap confirmation, spectral fingerprint | Indirect (LTM, keystroke attacks, Knocker) | Orange dot, ambient noise, about 4% CPU |
| Lid-angle sensor | Context key, motion veto | Measured (132°, integer degrees) | None significant |
| macOS key/trackpad events | Hard gate against typing | Standard API | Input Monitoring grant |
| Camera hand pose | Optional "where" prior | No laptop demo | Green light, power, lighting |
| Active ultrasound | Research-only | No laptop contact demo | Hinge decoupling, orange dot, pets |
| ALS, trackpad, Wi-Fi, display | None | Infeasible or negligible | n/a |

## A gyro-first pipeline with a nearest-prototype classifier

The architecture follows from the evidence. A **per-user LaunchAgent**, as yamete runs, owns the sensors. It runs in the user's login session so macOS can show the Input Monitoring prompt, and that grant is tied to the signing identity ([yamete](https://github.com/chipcolate/yamete)). There is no need for the root helper that olvvier-derived designs assume.

Three practical details matter:

- **Opening the device:** open it with options 0. Never use seize mode, which would steal reports from the system's own consumer ([yamete](https://github.com/chipcolate/yamete)).
- **Dropped reports:** track gaps using the u16 sequence counter in each report.
- **Timestamps:** stamp each sample with the HID report's `mach_absolute_time`. Audio buffers carry the same host clock through `AVAudioTime.hostTime` ([Apple AVAudioTime](https://developer.apple.com/documentation/avfaudio/avaudiotime)), so one calibration run of sharp knocks gives the constant IMU-to-audio offset by envelope cross-correlation.

The app has to be non-sandboxed, notarized and distributed directly. Private sensor access and synthetic event posting both rule out the Mac App Store ([Apple Developer Forums 789896](https://developer.apple.com/forums/thread/789896); [TrackWeight](https://github.com/KrishKrosh/TrackWeight)).

**Detection** is a two-stage design, borrowing TapNet's lesson that a peak gate is "a necessary (high recall) but not sufficient (low precision) signal" ([TapNet](https://ar5iv.labs.arxiv.org/html/2102.09087)).

Stage one is a cheap, high-recall trigger. It high-passes the gyro and accelerometer at about 5–10 Hz, runs STA/LTA or a peak/MAD score on the gyro magnitude, and sets thresholds at about twice the measured idle maximum, following yamete's guidance. Peaks within 80 ms are merged, followed by a refractory period of 150–300 ms.

Stage two applies layered rejection before any zone decision:

1. **The yamete-style torque test.** The gyro/accel ratio must be high.
2. **An OS input gate.** Candidates within about 200 ms of a key, trackpad or scroll event are suppressed. This uses a listen-only `CGEventTap`, which needs Input Monitoring ([Apple Developer Forums 707680](https://developer.apple.com/forums/thread/707680)).
3. **A lid-motion veto.** Candidates are suppressed when the lid angle changes.
4. **An explicit "not a tap" class.** It is trained on a minute or two of the user's own negatives: typing, trackpad clicks, desk knocks, lifting the machine, and audio playback. TapNet trained its event head on 26K such negatives ([TapNet](https://ar5iv.labs.arxiv.org/html/2102.09087)).
5. **An open-set distance check.** A tap is rejected if its distance to the nearest class prototype exceeds the 95th–99th percentile of the calibration distances. This is a lightweight version of OpenMax's idea ([Bendale & Boult](https://arxiv.org/abs/1511.06233)).

**Features** come from a window of about 100–150 ms anchored on the onset, which is 80–120 IMU samples. The core IMU vector covers the six high-passed channels:

- the signed peak of each axis and the sign of its first lobe;
- time-to-peak;
- cross-axis gyro ratios;
- the gyro/accel ratio;
- the signed integral of the first lobe;
- the decay slope;
- a handful of 0–400 Hz band energies.

Each vector is normalized by total energy so that tap force does not dominate, with log-energy kept as a separate feature. Before computing features, rotate the axes into a hinge-aligned frame using the lid angle, so a model trained at 120° stays meaningful at 100°. If audio is enabled, append 32–64 log-mel band energies, spectral centroid and decay from a 48 kHz window with voice processing off. Log the raw windows from day one, because they are the training set for any later learned model.

**The model** should match a dataset of 10–20 taps per zone. Start with z-scored features fed to distance-weighted kNN (k=3) and a nearest-centroid classifier, which is effectively a prototypical network without a learned embedding. Benchmark them against SVM-RBF, random forest, and a cross-correlation template matcher on the raw six-axis snippet, the direct analogue of location template matching. The comparison uses leave-one-tap-out cross-validation. Phone tap inference reached its results with exactly such classic ensembles ([survey](https://arxiv.org/pdf/2003.06159)). Deep models only pay off later: the keystroke CNN hit 95% with about 20 examples per class, but needed heavy augmentation and 1,100 epochs ([Harrison et al. 2023](https://arxiv.org/html/2308.01074)). For audio fusion, compare early fusion (concatenated, block-weighted features) with late fusion (summed per-modality log-probabilities), and keep late fusion as the fallback because it degrades gracefully when music or speech corrupts the audio.

**Context drift** is the main threat across every passive method:

- Lab-to-field accuracy drops by about 20% ([field study](https://unpaywall.org/10.1007%2F978-3-030-50309-3_43)) and by 15 points for Knocker ([Knocker](https://nmsl.kaist.ac.kr/projects/knocker)).
- Boundary conditions such as supports and warps shift acoustic results ([ALTo](https://ar5iv.labs.arxiv.org/html/2108.06837)).
- Toffee depends on the hard surface the device rests on ([Toffee](https://chrisharrison.net/index.php/Research/Toffee)).

Key the stored prototypes by measurable context: a lid-angle bin of about 10–15°, a desk-versus-lap flag inferred from low-frequency accelerometer variance, and AC versus battery power. Fall back to the nearest key when an exact match is missing. When the reject rate climbs, ask for a one-tap-per-zone re-anchor and shift the prototypes by the mean feature delta instead of retraining. In Swift, a hand-written kNN is trivially updatable. Core ML's updatable kNN exists, but nobody verified its current status on macOS 26/27 ([coremltools](https://cymbalrush.github.io/coremltools/docs-guides/_sources/source/updatable-model-examples.rst)).

**Output** goes through `CGEventPost`, which needs Accessibility approval ([Apple Developer Forums 724603](https://developer.apple.com/forums/thread/724603)), or through BetterTouchTool's `btt://trigger_named` or a `hammerspoon://` URL. Emitting unused F13–F20 keys lets Karabiner or BTT own the action mapping ([BTT](https://docs.folivora.ai/docs/scripting/url-scheme/); [Hammerspoon](https://www.hammerspoon.org/docs/hs.urlevent.html)). Bind zones to forgiving, idempotent commands such as Mission Control, play/pause or page scroll, and show a brief highlight of the detected zone as feedback. Latency is dominated by waiting for the tap window. TapNet spent about 105 ms waiting and 0.56 ms on inference ([TapNet](https://ar5iv.labs.arxiv.org/html/2102.09087)), so expect roughly **130–170 ms from tap to action**. That is fine for discrete commands.

## Expect 2×2 to work and 3×3 to be a stretch

No measured accuracy exists for any lid-zone layout on any MacBook. The table below is extrapolated from the cited analogues, with your M3 Air's base-mounted IMU, a single fixed context, and a per-user calibration assumed. It is a set of hypotheses to falsify in the first experiments, not a forecast.

| Layout | Same-context accuracy (extrapolated) | Uncontrolled use (extrapolated) | Basis |
|---|---|---|---|
| Tap detected vs not | High for firm taps; fingertip taps unknown | False positives dominated by desk knocks | yamete 35/40 slaps at 0 FP; idle gyro std 0.2–1.5 °/s |
| Left / right (2 zones) | ≥95% | 85–90% | Sign of a torque component flips; Toffee-style bearing cues |
| Left / centre / right or 2×2 | 85–95% | 70–85% | TapPrints up to 90%; Knocker 92–98% with 20 shots |
| 2×3 (top two rows emphasized) | 80–90% | 65–80% | Adjacent-zone confusion; field drop of about 20% |
| 3×3 | 65–85% | 50–70% | Weak bottom row near the hinge; TapNet's fine-grid collapse |

The calibration budget follows the same evidence: about 20 knocks per class for Knocker and 25 presses per key in the keystroke study ([Knocker](https://nmsl.kaist.ac.kr/projects/knocker); [Harrison et al. 2023](https://arxiv.org/abs/2308.01074v1)). Plan on 10–20 taps per zone. For a 3×3 that is 90–180 taps, roughly two to three minutes, plus one to two minutes of negatives. The real answer comes from your own learning curve at 3, 5, 10 and 20 shots. The calibration UI should **auto-merge zones** that the held-out check confuses, so the user ends up with the finest grid their machine and tapping style actually support. The design is then driven by measured confusion rather than by an aspirational 3×3.

Two uncertainties could move these numbers a lot. The first is fingertip SNR: if light taps barely clear the 0.2–1.5 °/s idle gyro noise, users will drift toward harder taps. Avoid that, because pressure damage to LCD and mini-LED panels is a known, usually unwarrantied failure ([repair forum](https://www.app-elearn.com/forum/discussion/8734/macbook-screen-pressure-damage-can-it-be-fixed-without-replacing-the-panel)), so knuckle taps near the stiff top and side edges are the safer fallback. The second is hinge filtering: the hinge's friction and compliance could blur the lateral twist that carries left/right information. A further risk is that the sensor path is undocumented and could break with any macOS update, although it has survived from macOS 13 through 27.0.1 so far ([yamete](https://github.com/chipcolate/yamete); [olvvier](https://github.com/olvvier/apple-silicon-accelerometer)).

## Four phases, starting with an afternoon of labeled taps

| Phase | Goal | Work | Exit criterion |
|---|---|---|---|
| 0. Signal check (1–2 days) | Prove fingertip taps are visible and separable | Extend `probe2.py` to log accelerometer, gyroscope and lid angle with labels; record taps per zone | Gyro peak ≥3–5× idle p99.9; visible per-zone sign or ratio clusters |
| 1. IMU-only prototype (1 week) | Offline zone classifier | Python: numpy/scipy, scikit-learn; kNN, centroid, SVM, RF, template matcher; leave-one-out CV; learning curves | 2×2 or L/C/R ≥90% same-context; confusion matrix decides the grid |
| 2. Robustness and fusion (1–2 weeks) | Survive real use | Negatives corpus; OS-event and lid gates; context keys; optional passive mic ablation | False triggers <1 per hour of typing and desk use; drop <15 pts across lid angles |
| 3. Native app | Daily-usable tool | Swift LaunchAgent + menu-bar app; IOHID dispatch queue; vDSP features; Swift kNN; calibration overlay; BTT/Hammerspoon output | Under 170 ms latency, about 3–4% CPU, re-anchor flow works |
| 4. Optional research | Extra spatial cues | Camera hand-pose prior; ultrasonic sweep test | Only if it beats Phase 2 by a measured margin |

The first experiments are concrete and cheap. Each one reuses the probe's wake-and-open sequence.

**Experiment 1: idle baseline.** Record 60 s of idle data with the lid at its usual angle on your desk. Compute the per-axis p99.9 of the high-passed gyro and accelerometer signals. Those numbers become your thresholds, replacing yamete's values, which were measured on an M4 Pro.

**Experiment 2: labeled taps.** Mark a 3×3 grid on the lid back (or the display, if you accept the glass risk) with removable tape. Record 20 fingertip-pad taps and 20 knuckle taps per cell, with a metronome or on-screen prompt so labels align by time. That is 360 taps, about 15 minutes.

**Experiment 3: signal analysis.** Using the Experiment 2 data, plot each cell's mean gyro waveform per axis. Check whether a left/right sign flip and a top/bottom magnitude-ratio gradient appear as the physics predicts. Also compute the accelerometer's power spectrum during taps to confirm or refute the low-pass filtering seen at idle.

**Experiment 4: classifier and grid choice.** Run leave-one-tap-out kNN and SVM on the hand-crafted features. Draw confusion matrices and learning curves for 3×3, then merge cells into 2×3, 2×2 and L/C/R and re-score. The best-performing merge sets your grid.

**Experiment 5: context shift.** Train at one lid angle and test at ±20°. Train on the desk and test on your lap. Record two minutes each of typing, trackpad clicking and desk knocks to measure false-trigger rates.

**Experiment 6: microphone ablation.** Repeat Experiment 2 with simultaneous 48 kHz mic capture, voice processing off, to quantify what audio adds.

Only if all of that leaves a gap is it worth trying the 17–23.5 kHz sweep test to measure whether touching the lid changes the speaker-to-mic transfer function at all.

## Conclusion

The question shifts from "which sensor can see where I touched?" to "which sensor feels *how the machine was twisted*?" No built-in sensor observes the contact point. The camera can't see the glass, the mic array is collapsed to one channel, and the panel has no digitizer. The base gyroscope, though, measures the rigid-body consequence of a lid tap at about 800 Hz, and yamete's slap data show that consequence is distinctive enough to reject desk bumps that are physically larger. Zone tapping is therefore really a hinge-torque fingerprinting problem. It is best solved like location template matching: per machine, per context, with a nearest-prototype model that the user can re-anchor in seconds. It is not a geometry problem to be solved with TDOA.

The practical implication is to let measured confusion, not ambition, set the grid. Treat 3×3 as an outcome the calibration flow can unlock if your taps support it, and build the product around the 2×2 or L/C/R layout that the physics most clearly favors. Phase 0 is cheap, and it answers the two unknowns that decide everything else: whether fingertip taps clear the gyro noise floor, and whether the hinge preserves the left/right twist.
