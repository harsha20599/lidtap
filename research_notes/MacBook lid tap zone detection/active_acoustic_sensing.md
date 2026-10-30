# Active acoustic / ultrasonic sensing with a device's own speakers and mics, applied to touch zones on a MacBook lid/display

Scope note: these notes cover active sensing, meaning the device emits a known inaudible signal and analyzes how a touch changes the received signal. Passive tap acoustics and accelerometer methods belong to other researchers. One finding comes from a **local CoreAudio measurement on the user's own machine** (MacBook Air 13-inch M3, model identifier Mac15,12, Darwin 27). It is labelled "[Local CoreAudio query]" because it has no URL.

---

## 1. Key papers: what they sensed, how many zones, accuracy, latency, and whether light touch or hold works

### Takeaway
The literature shows high accuracy (95–99.7%) for classifying a small number of touch locations or gestures (about 3–6 classes) with active acoustic sensing. Almost all of it uses either contact transducers glued to the object (Touch & Activate, VibSense, SAWSense) or a phone where speaker and mic sit in one small rigid body (ForcePhone, VSkin). Systems that use only built-in speakers and mics in air (SoundWave, FingerIO, LLAP, Strata) track motion near the device at mm–cm accuracy. They detect movement, not static contact. No published, evaluated system detects touches on a laptop lid or display using only the laptop's built-in speakers and mics.

### Cited Findings
**Contact or structure-borne systems (closest in spirit to "touch damps the lid")**
- **Touch & Activate** (Ono, Shizuki, Tanaka; UIST 2013, Best Paper, pp. 31–40). It attaches a vibration speaker and a piezo microphone to an object. With per-user training it reached 99.6% accuracy on 5 touch gestures on a plastic toy and 86.3% on 6 hand postures. Walk-up accuracy, with no per-user training, was 97.8% and 71.2% — [Tsukuba IPLab](https://www.iplab.cs.tsukuba.ac.jp/en/paper/6151b7ff551fd46e82abdb1b); [AMiner](https://www.aminer.org/pub/53e9a25cb7602d9702b6228c/touch-activate-adding-interactivity-to-existing-objects-using-active-acoustic-sensing); [UIST 2013 program](https://uist.acm.org/uist2013).
- Touch & Activate excitation is described by a secondary source as largely inaudible 20–40 kHz tones. The primary paper's exact sweep parameters were not verified — [bloomfieldknoble.com (secondary)](https://www.bloomfieldknoble.com/touch/). This band is above what laptop speakers emit well (see section 3), so the original design cannot be copied directly.
- **ForcePhone** (Tung & Shin, MobiSys 2016). The phone's own speaker plays a tone above 18 kHz, and the phone's own mic picks up how the tone travels through the phone body. Pressing on the screen or body changes the received signal. Estimated force correlated above 0.9 with applied force, with about 54 g error when stationary. In the demo, users chose between 2 force levels with over 97% accuracy. False detections were filtered using touchscreen location and timing plus the accelerometer — [MobiSys paper PDF](https://rtcl.eecs.umich.edu/rtclweb/assets/publications/2016/paper-mobisys-final_refined_by_apple.pdf); [demo PDF](https://rtcl.eecs.umich.edu/rtclweb/assets/publications/2016/tun2016demo.pdf); [UMich news](https://news.umich.edu/?p=23942). This is the strongest evidence that pressing changes a structure-borne inaudible signal, but it was measured on a single rigid phone body.
- **VSkin** (Sun, Zhao, Wang, Xie; MobiCom 2018, pp. 591–605). It senses touch gestures on the back and other surfaces of a phone, using both structure-borne sound (through the body) and air-borne sound. Tap detection accuracy was 99.65% and finger-movement tracking accuracy was 3.59 mm. It ran as real-time Android apps on commercial phones — [paper PDF](https://samsonsjarkal.github.io/KeSun/files/mobicom18_vskin.pdf); [researchr](https://researchr.org/publication/SunZWX18). I could not extract the full PDF text (no PDF tools available), so VSkin's phone models, band, latency and hold or force results are unverified.
- **VibSense** (Stevens/Rutgers) is vibration-based touch localization and object identification on ordinary surfaces using a vibration motor and receiver. It reported over 95% accuracy across use cases — [VibSense PDF](https://personal.stevens.edu/~ychen6/papers/VibSense%20Sensing%20Touches%20on%20Ubiquitous%20Surfaces%20through%20Vibration.pdf). **VibWrite** (same group) does finger-input authentication on solid surfaces: over 95% within two trials, under 3% false positives. Touchscreens are explicitly excluded — [Rutgers](https://scholarship.libraries.rutgers.edu/esploro/outputs/conferenceProceeding/VibWrite-Towards-Finger-input-Authentication-on-Ubiquitous/991031758082404646); [eeNews](https://www.eenewseurope.com/en/smart-access-security-system-senses-finger-vibrations/).
- **SAWSense** (UMich, CHI 2023 Best Paper) is passive, not active. It uses bone-conduction Voice Pickup Units that detect only surface acoustic waves and reject airborne sound. Taps, scratches and swipes were recognized with 97% accuracy — [UMich EECS news](https://eecsnews.engin.umich.edu/sensor-enables-high-fidelity-input-from-everyday-objects-human-body/); [New Atlas](https://newatlas.com/science/sawsense-surface-acoustic-waves-interface).
- **Acoustruments** (Laput, Brockmeyer, Hudson, Harrison; CHI 2015 Best Paper) attaches passive plastic tubes between a phone's speaker and mic. Blocking holes or changing tube length or diameter alters an ultrasonic signal, and the system reached 99% accuracy with minimal training — [Disney Research PDF](https://la.disneyresearch.com/wp-content/uploads/Acoustrument-Passive-Acoustically-Driven-Interactive-Controls-for-Hand-Held-Devices-Paper.pdf); [CMU news](https://www.cmu.edu/news/stories/archives/2015/april/acoustruments-for-handheld-devices.html). This is relevant as a "touch occludes an acoustic path" analogy.
- An academic active-acoustic touch-localization line on elastic panels (Univ. Rochester, *J. Sound & Vibration*) uses a force exciter mounted to the panel — [NSF PAR](https://par.nsf.gov/servlets/purl/10534098).
- Patents describe the same idea for displays. US8519982B2, "Active acoustic touch location for electronic devices", matches a captured acoustic signature against stored per-location signatures. Related filings cover active acoustic multi-touch and swipe detection using haptic transducers — [Google Patents US8519982](https://patents.google.com/patent/US8519982); [Justia 20120081337](https://patents.justia.com/patent/20120081337). The assignee was not verified.

**Air-borne systems using built-in speakers and mics (motion, not contact)**
- **SoundWave** (Gupta, Morris, Patel, Tan; CHI 2012; DOI 10.1145/2207676.2208331) is the original laptop work. It emits 18–22 kHz tones from the laptop's own speakers and senses gestures from Doppler shift within about 1 m. The paper says most laptop and phone speakers top out around 22 kHz. In practice it chose 18–19 kHz — [paper PDF](https://people.ece.cornell.edu/land/courses/ece4760/FinalProjects/f2012/alt53_lw354/alt53_lw354/files/GuptaSoundWaveCHI2012.pdf); [UW mirror](https://modernmobile.cs.washington.edu/docs/soundwave.pdf).
- **FingerIO** (UW, CHI 2016) tracks a finger in 2D using a phone's own speaker and mics. Average accuracy is 8 mm on a phone and 12 mm on a smartwatch. A survey lists 169 fps — [FingerIO site](https://fingerio.cs.washington.edu/); [survey arXiv:1901.03450](https://arxiv.org/pdf/1901.03450).
- **LLAP** (Wang, Liu, Sun; MobiCom 2016) uses phase-based tracking with a 17.5–20.3 kHz signal. Accuracy is 3.5 mm in 1D and 4.6 mm for 2D drawing, with about 15 ms latency on commercial phones — [LLAP demo PDF](https://samsonsjarkal.github.io/KeSun/files/mobicom16_llapdemo.pdf); [survey](https://arxiv.org/pdf/1901.03450).
- **Strata** (MobiSys 2017, Galaxy S4) claims to beat LLAP and FingerIO. In its own re-evaluation, LLAP had 0.7 cm 1D error and 1.9 cm 2D error, and FingerIO did worse — [Strata PDF](https://www.cs.sjtu.edu.cn/~yichao/pmwiki/assets/publications/mobisys17_strata.pdf). Different test setups make these numbers hard to compare across papers.
- **AudioGest** (IEEE TMC) recognized 6 hand gestures with one built-in speaker and one mic — cited in [runtimewire article](https://runtimewire.com/article/openai-astra-macbook-sonar-gesture-scroller).

### Inferences
- **Light touch and hold.** The Doppler and phase trackers (SoundWave, LLAP, FingerIO, Strata) respond to motion. A finger resting still on the lid produces no Doppler shift and almost no phase change, so a hold is invisible to them. Detecting a hold needs a static channel-response method instead. That method compares the current impulse or frequency response with a no-touch baseline, as Touch & Activate, ForcePhone and VSkin effectively do. Such baselines drift with temperature, lid angle, hand positions on the palm rest and room reflections.
- **Drags.** On phones, VSkin-style mm tracking of a moving finger is shown. On a MacBook display, movement tracking near the lid surface is more plausible than static contact sensing, because a moving finger reflects sound by the air-borne path.
- **Zones.** Published contact-transducer systems handle about 5–6 classes at over 95%. For a lid sensed only by built-in hardware, a realistic hypothesis is 2–4 coarse zones (for example left, right, top bezel, none). This is speculative, and no paper demonstrates it.

### Gaps
- Exact Touch & Activate sweep parameters, plus SoundWave gesture accuracy figures (the PDFs were not text-extracted).
- "EchoFlex", "BackTap" (acoustic), "UltraTouch", "SonicTouch", "SonarID", "TouchPrint" and "Expressive touch via inaudible sound": the searches returned nothing usable, and I found no reliable sources under those names. iOS "Back Tap" is accelerometer-based (see the PalmEcho note in section 5). VSkin is the closest match to "expressive touch via inaudible sound on smartphones".
- VSkin latency, band and phone models are unverified.

---

## 2. Structure-borne vs air-borne paths, signal design, and fit to a MacBook geometry

### Takeaway
On phones, a press works because speaker, mic and touched surface are one rigid body. The structure-borne path arrives before the air-borne one, so the two can be separated by delay (VSkin). On a MacBook, the display lid joins the base only through the hinge. Any touch effect on a structure-borne path from base speakers to mics is likely weak. The air-borne reflection or occlusion path, where a finger near or on the lid changes reflections reaching the mic, may dominate. Standard signal designs are a linear chirp or sweep plus matched filter to get an impulse response, OFDM (FingerIO), Zadoff-Chu or other pseudo-noise sequences, or CW tones for Doppler and phase (SoundWave, LLAP). All of them sit in about 17.5–21 kHz on commodity hardware.

### Cited Findings
- VSkin explicitly combines structure-borne and air-borne sound to sense touches on phone surfaces — [VSkin PDF](https://samsonsjarkal.github.io/KeSun/files/mobicom18_vskin.pdf).
- ForcePhone relies on sound travelling through the phone body from its own speaker to its own mic — [UMich news](https://news.umich.edu/?p=23942).
- Bands and waveforms in use:
  - SoundWave: CW tones in 18–22 kHz, in practice 18–19 kHz, sensed by Doppler — [SoundWave](https://people.ece.cornell.edu/land/courses/ece4760/FinalProjects/f2012/alt53_lw354/alt53_lw354/files/GuptaSoundWaveCHI2012.pdf).
  - LLAP: 17.5–20.3 kHz, sensed by phase — [LLAP](https://samsonsjarkal.github.io/KeSun/files/mobicom16_llapdemo.pdf).
  - FingerIO: OFDM echoes — [FingerIO](https://fingerio.cs.washington.edu/).
  - Strata: known inaudible signals reflected by the finger, sensed by channel-tap phase — [Strata](https://www.cs.sjtu.edu.cn/~yichao/pmwiki/assets/publications/mobisys17_strata.pdf).
- A draft for exactly this laptop idea ("PalmEcho", J. H. Kim; an unfiled provisional-patent drawing draft, **not an evaluated system**) proposes the following, with no results reported:
  - an 18–22 kHz swept-sine chirp of about 1 s, emitted at 48 kHz and captured at 96 kHz on Apple Silicon;
  - matched-filter deconvolution, with the first 30 ms of the response turned into an 8-dimensional feature vector;
  - a k-NN classifier (k = 3) over 4 classes: left palmrest, right palmrest, lid/bezel, and no tap;
  - a self-imposed gate of at least 70% leave-one-out accuracy before the draft is promoted;
  - a compute budget of 5 ms or less per chirp, but about 1 s of emission per chirp, so latency would be poor.

  It leaves the structure-borne vs air-borne model underspecified — [PalmEcho draft](https://guccigrandfather.pages.dev/palmecho). This is a personal page on an unusual domain, so treat it as low-authority.

### Inferences
- **Delay separation.** At an assumed 48 kHz, one sample is about 7 mm of air path. Sound in an aluminium or glass structure travels roughly 10–15 times faster than in air (general physics, not sourced here). Structure-borne arrivals should therefore come within the first 1–2 ms. Air-borne reflections from a finger on the lid, about 15–30 cm away by speaker-to-finger-to-mic, should arrive around 0.5–1 ms. These windows overlap, so separating the paths by delay alone will be hard. A short chirp (about 5–20 ms) repeated at 20–50 Hz gives a frame-level channel estimate that supports both baseline-differencing (for holds) and phase-differencing (for drags).
- **Why short frames.** PalmEcho's 1 s chirp is far too slow for interaction. LLAP and Strata-style continuous signals with roughly 10 ms frames are the right model for latency.
- **Signal shaping.** Keep the emission continuous, or use windowed or tapered chirps, so on/off transitions do not create audible clicks.
- **Hinge coupling.** The hinge is a damped, compliant joint. Touch-induced damping of lid vibration will probably be a small change on the base-to-base speaker-to-mic path, below the drift from lid angle and palm-rest contact. This is untested.
- **Fallback sensing.** On models with speakers near the hinge or keyboard and mics in the base, the most plausible usable signal is the air-borne one. That means occlusion and reflection changes when a hand approaches or touches the lowest part of the display, and Doppler or phase change during a drag. That supports proximity or "touch-ish" detection rather than true contact detection.

### Gaps
- Exact speaker and mic positions on current MacBook Air and Pro models (teardown data was not retrieved). Apple's spec page does not give speaker locations — [Apple MacBook Air 15" M3 specs](https://support.apple.com/en-us/118552).
- No measurements found of lid vibration modes or structure-borne transfer through a MacBook hinge.

---

## 3. MacBook audio hardware and macOS practicalities

### Takeaway
On this M3 MacBook Air, CoreAudio exposes the built-in mic as **1 input channel** (Apple's 3-mic beamformed array, already mixed down) and the speakers as 2 output channels. Both support nominal rates of 44.1, 48, 88.2 and 96 kHz. Laptop speakers produce usable energy in about 18–20 kHz with steep falloff above about 21 kHz. That caps the usable band to roughly 17.5–21 kHz whatever the sample rate. Apps must avoid Apple's voice-processing I/O, because its echo cancellation would subtract the app's own probe signal. Any capture shows the orange mic indicator, which cannot be disabled.

### Cited Findings
- **[Local CoreAudio query]** on MacBook Air 13-inch M3 (Mac15,12):

  | Device | Channels | Nominal rates (Hz) | Latency and safety offset (frames) | Buffer size range (frames) | Current rate |
  |---|---|---|---|---|---|
  | MacBook Air Microphone | 1 in | 44100, 48000, 88200, 96000 | input safety offset 50 | 14–4096 | 44100 |
  | MacBook Air Speakers | 2 out | 44100, 48000, 88200, 96000 | output latency 148, output safety offset 146 | 29–4096 | 96000 |

  The query used `kAudioDevicePropertyAvailableNominalSampleRates`, `kAudioDevicePropertyStreamConfiguration`, latency, safety-offset and buffer-range properties via a small C program. Mic and speakers appear as **separate CoreAudio devices**.
- Apple specs for MacBook Air 15" M3 list a "Three-mic array with directional beamforming" and a "Six-speaker sound system with force-cancelling woofers", with no locations given — [Apple support 118552](https://support.apple.com/en-us/118552). That the array is exposed as a single channel matches the local query.
- An old (about 2008) Apple spec quoted on forums gave internal-mic rates of 44.1, 48 and 96 kHz at 16, 20 or 24 bit. No official current frequency-response spec exists, and forum users could not find one — [Apple Discussions](https://discussions.apple.com/thread/1973943?page=1); [MacRumors](https://forums.macrumors.com/threads/macbook-microphone-frequency.551132). MEMS mics are often usable above 20 kHz but this is rarely documented — [EEVblog](https://www.eevblog.com/forum/dodgy-technology/company-embeds-inaudible-sounds-in-web-pages-to-identify-users-across-devices/) (forum, weak).
- **Speaker output at near-ultrasound.**
  - A laptop at full volume gave 64.1, 64.3 and 62.9 dB SPL at 20 cm for 18, 19 and 20 kHz tones, over a 48.8 dB noise floor. The tones were inaudible to the experimenters, and built-in responses are typically non-flat — [arXiv:2103.11261](https://arxiv.org/pdf/2103.11261).
  - Best laptop-speaker performance was at 18–19.5 kHz, with significant attenuation above 21 kHz — [SmartAttack arXiv:2506.08866](https://arxiv.org/pdf/2506.08866).
  - Commodity near-ultrasound use cases sit in 18–24 kHz — [NCC Group whitepaper](https://nccgroup.com/media/00rjhgp1/_ultrasound-whitepaper-v10.pdf).
- **Voice processing and Mic Mode.** `setVoiceProcessingEnabled(_:)` on `AVAudioInputNode` / `AVAudioIONode` turns Apple's voice-processing I/O on or off, and the engine must be restarted after a change — [Apple AVAudioIONode docs](https://developer.apple.com/documentation/avfaudio/avaudioionode.md); [LiveKit audio guide](https://www.mintlify.com/livekit/client-sdk-swift/guides/audio-management). Using Apple's voice-processing APIs is what exposes the user Mic Mode controls (Standard, Voice Isolation, Wide Spectrum) for that app — [WWDC23 "What's new in voice processing"](https://wwdcnotes.com/notes/wwdc23/10235). Side effects reported by developers:
  - enabling voice processing changed the mic channel count from 1 to 5 — [Apple Dev Forums 771530](https://developer.apple.com/forums/thread/771530);
  - errors occur when the input and output devices differ — [Apple Dev Forums 128518](https://developer.apple.com/forums/thread/128518).
- **Mic indicator.**
  - An orange dot next to Control Center shows whenever the mic is in use, and Control Center lists the apps using it — [Apple Mac Help: Control Center](https://support.apple.com/en-au/guide/mac-help/mchl50f94f8f).
  - macOS has no built-in way to disable the dot. Only unofficial tools like "undot" can hide it — [TechFinitive](https://www.techfinitive.com/explainers/turn-off-orange-dot-mac-screen/); [AppleInsider](https://appleinsider.com/articles/21/12/22/a-prominent-orange-dot-in-macos-monterey-is-causing-problems-for-artists).
- **Audibility.** Quiet's near-ultrasonic modes (17 kHz and up) are "virtually inaudible to adults" — [Quiet profiles](https://quiet.github.io/docs/quiet/profiles). Commenters note 18 kHz can be audible to some, especially younger, listeners — [Hackaday (comments, weak)](https://hackaday.com/2012/03/21/doppler-effect-lets-you-add-gestures-to-your-computer).
- **Other platforms.** Firefox WebAudio resamples input to 32 kHz, which kills ultrasonic reception in that browser — [Quiet blog](https://quiet.github.io/quiet-blog/2016/03/29/quiet.html). Native apps avoid this.

### Inferences
- **Disable voice processing.** It is effectively mandatory to leave voice processing off (a plain AVAudioEngine or AUHAL input). Voice-processing I/O includes acoustic echo cancellation designed to remove the device's own speaker output, which is exactly the probe signal.
- **Sample rate.** 96 kHz is a nominal rate. Whether the built-in mic delivers real content above 24 kHz, or whether its path is low-passed or resampled internally, is unknown. It barely matters, because speaker output collapses above about 21 kHz. A 48 kHz pipeline with a 17.5–21 kHz probe is the sensible default. 96 kHz may still help with timing resolution and anti-alias headroom.
- **Clocking.** Mic and speakers are separate devices. To keep a stable phase reference, use an Aggregate Device or a single AVAudioEngine graph driving both, and estimate the speaker-to-mic delay by cross-correlating each frame. Output latency plus safety offset is about 294 frames (about 3 ms at 96 kHz), but the true acoustic round trip must be measured.
- **Unknown DSP.** The single exposed mic channel is post-beamformer, so it is a fixed spatial filter of unknown design. Apple may also apply non-user-visible processing such as high-pass filtering or AGC on the HAL path. This needs empirical checking with a sweep.
- **Suggested first experiment** (not run here, to avoid recording the user's environment without consent):
  - Play a 17–23.5 kHz log sweep at moderate volume and record at 96 kHz with voice processing off.
  - Compute the transfer function, then repeat while touching different lid zones. This directly measures the usable band and touch sensitivity.
  - Use the `sounddevice` `playrec()` function, or an AVAudioEngine graph with both nodes.
- **Permissions.** Microphone access needs TCC user consent and an `NSMicrophoneUsageDescription` string in a bundled app (standard macOS practice, not sourced above). The orange dot would be permanently visible during sensing, which is a significant UX and privacy cost.
- **Pets.** Dogs and cats hear well above 20 kHz. A continuous 18–21 kHz tone may bother them. This is not sourced here.

### Gaps
- No official or measured frequency response for Apple Silicon MacBook mics or speakers above 20 kHz.
- Whether the macOS HAL applies low-pass, high-pass or AGC filtering on the built-in mic outside voice processing.
- Whether per-capsule raw access to the 3-mic array is possible. None was found, and the local query shows only 1 channel.
- Power cost of continuous play and record. No measurements found. The DSP itself is small (PalmEcho budgets 5 ms or less of compute per frame), but the speaker amp and mic staying awake continuously are the likely cost.
- Whether Wide Spectrum or Voice Isolation affects apps that do not use voice processing. WWDC23 implies it does not.

---

## 4. Open-source code and play-and-record tooling

### Takeaway
Reference code exists for the core algorithms: LLAP on iOS, Doppler gesture sensing, and the ultrasonic modems Quiet (on liquid-dsp) and ggwave. None of it targets touch on a laptop. A prototype on macOS would be Python (`sounddevice` / PortAudio `playrec`, NumPy/SciPy) or Swift (AVAudioEngine with voice processing off).

### Cited Findings
- **LLAP.** The iOS implementation of LLAP (MobiCom 2016) is at github.com/Samsonsjarkal/LLAP, with a mirror at github.com/tongchen126/llap. The repo was last updated about 8 years ago — [relatedrepos listing](https://relatedrepos.com/gh/Samsonsjarkal/LLAP); [mirror](https://gh.r-mj.com/tongchen126/llap).
- **Sound_Doppler_Gesture_Sensing.** This repo uses commodity speakers and mics for in-air gesture sensing — [GitHub](https://github.com/Xiangyu-Gao/Sound_Doppler_Gesture_Sensing).
- **Quiet / libquiet.** A data-over-sound modem built on liquid-dsp, with JSON profiles that include near-ultrasonic modes (17 kHz and up). It also has quiet-js and QuietModemKit for iOS and macOS — [How it works](https://quiet.github.io/docs/quiet/how); [profiles](https://quiet.github.io/docs/quiet/profiles); [quiet-py on PyPI](https://pypi.org/project/quiet-py). liquid-dsp is a general SDR DSP library — [GitHub mirror](https://github.com/f4exb/liquid-dsp).
- **ggwave.** An FSK data-over-sound library with Reed-Solomon coding, 8–16 B/s, and ultrasound protocols. It has Python bindings on PyPI — [PyPI ggwave](https://pypi.org/project/ggwave/); [Hackster](https://www.hackster.io/news/georgi-gerganov-s-ggwave-offers-air-gapped-comms-between-microcontrollers-smartphones-via-sound-3b2020c00ccd).
- **Doppler gesture sensing in JavaScript** (WebAudio, SoundWave-style) — [Hackaday 2015](https://hackaday.com/2015/03/13/doppler-gesture-sensing-in-javascript).
- **Chirp processing on OS X.** A blog post discusses practical problems with audio chirp processing on OS X — [henryomd blog](https://henryomd.blogspot.com/2017/03/audio-chirp-processing-problems-on-os-x.html). The content was not fetched.

### Inferences
- **Modems are a starting point, not a solution.** Quiet and ggwave are communication systems, not sensing systems. They are useful for proven near-ultrasonic emit and receive plumbing on macOS, but provide no channel-estimation or touch logic.
- **Best algorithmic templates.**
  - LLAP for phase-based drag tracking.
  - FingerIO and Strata for frame-based channel impulse response (CIR) estimation with OFDM or pseudo-noise sequences.
  - Touch & Activate for a sweep plus FFT-feature classifier.
- **Prototype stack.** Python with `sounddevice.playrec()` at 48 or 96 kHz, a continuous 10–20 ms chirp or Zadoff-Chu frame in 18–21 kHz, matched filtering, CIR differencing against a baseline, and an SVM or k-NN classifier per zone.

### Gaps
- No public code found for FingerIO, Strata, VSkin or ForcePhone.
- No macOS-specific ultrasonic sensing library found.

---

## 5. Demos of ultrasonic touch or gesture sensing on a laptop specifically

### Takeaway
Laptop demos exist only for in-air Doppler gestures: SoundWave in 2012, and a 2026 MacBook "sonar scroller" demo on X. The only laptop chassis-touch proposal found (PalmEcho) is an unevaluated draft. No demonstration of touch-zone detection on a MacBook display using built-in audio hardware was found.

### Cited Findings
- **SoundWave** ran on commodity laptops. Its video showed playing Tetris with gestures and waking the display when a user approaches — [SoundWave PDF](https://people.ece.cornell.edu/land/courses/ece4760/FinalProjects/f2012/alt53_lw354/alt53_lw354/files/GuptaSoundWaveCHI2012.pdf); [Hackaday 2012](https://hackaday.com/2012/03/21/doppler-effect-lets-you-add-gestures-to-your-computer).
- **2026 MacBook sonar scroller.** On 9 Sep 2026, Emanuel Perez posted on X a Mac app, reportedly built with an OpenAI model, that emits a 20 kHz tone from the MacBook's own speakers and reads Doppler shifts at the mic to scroll with hand motions. The article does not give the model, latency or code. It notes the demo does not test differences in speaker response, mic placement or audio processing across Apple's lineup — [runtimewire](https://runtimewire.com/article/openai-astra-macbook-sonar-gesture-scroller). This is a single-source, unverified report, but it suggests 20 kHz Doppler is receivable on at least one MacBook.
- **PalmEcho** is a draft provisional patent for laptop chassis-tap zones using built-in speakers and mics, with an 18–22 kHz chirp, 96 kHz capture and 4 classes including lid/bezel. It reports no results. It cites Touch & Activate and Apple's accelerometer-based Back Tap as prior art — [PalmEcho draft](https://guccigrandfather.pages.dev/palmecho).
- **Related patents.** Technical-disclosure and patent filings describe speaker-ping, mic-reflection sonar for presence detection on devices — [TDCommons](https://www.tdcommons.org/dpubs_series/5342); [presence-detection patent](https://ipiq.io/patents/2938592).

### Inferences
- **Feasibility.** Proximity, approach and drag-near-screen sensing on a MacBook with built-in hardware is demonstrated, at least informally. Detecting light contact or a hold on the display glass, in separate zones, is unproven. It would need first-principles experiments, such as the sweep test in section 3.
- **Expected performance.** A realistic first target is binary detection of "hand on or very near lower display area vs not", plus left vs right. Fine zone grids or light-touch detection should be treated as high-risk.

### Gaps
- No peer-reviewed evaluation of any acoustic touch system on a laptop lid or display.
- No measured latency or accuracy for the 2026 MacBook demo.
