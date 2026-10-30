# Passive Tap/Knock Localization on Rigid Surfaces with Few Sensors (as applied to MacBook-lid tap zones)

Scope note: this covers passive sensing only, meaning listening for the tap. Active ultrasonic sensing is covered elsewhere. Some systems below are active (VibWrite) or use emitted pulses. Each one is flagged where it appears.
Method note: I used about 20 search and fetch calls. Several primary PDFs (Knocker IMWUT'19, ALTo, MIT Paradiso) came back as unreadable binary or refused the connection. Where I could not see a paper's own numbers, I relied on abstracts, project pages and secondary summaries, and say so.

## Q1. Location Template Matching (LTM) / time-reversal: how does one sensor localize, and how accurately?

### Takeaway
LTM/time reversal localizes a tap with a single sensor by treating the plate's reverberant impulse response as a per-location fingerprint. A one-time "learning phase" records taps at each target location, and a new tap is assigned to the best cross-correlation match. The number of distinguishable locations scales with the mean wavelength of the detected waves. This is the closest physical analogue to "N zones on a lid with 1 mic/IMU". The cost is per-device calibration and sensitivity to anything that changes the plate's boundary conditions. I found no hard accuracy figures for the original Ing/Fink single-sensor work in accessible sources.

### Cited Findings
- **LTM mechanism.** One sensor on the surface records a set of pre-collected touches tagged with their locations. A new touch is matched to the closest recording by cross-correlation. — [Korean LTM comparison study (koreascience)](https://koreascience.kr/article/CFKO201431749163690.pdf); [Location template matching on rigid surfaces for HCI touch interface applications (NTU)](https://nanyangtechnologicaluniv.demo.elsevierpure.com/en/publications/location-template-matching-on-rigid-surfaces-for-human-computer-t)
- **Main limit.** LTM touch detection is constrained to a finite number of pre-recorded contact points. It is a classifier over trained locations, not a continuous localizer. — [koreascience LTM study](https://koreascience.kr/article/CFKO201431749163690.pdf)
- **Resolution depends on wavelength.** In time-reversal interactive objects, "the number of possible touch locations at the surface of objects is directly related to the mean wavelength of the detected acoustic wave". The time-reversal method compares the interaction signal "with respect to a pre-recorded (learning phase) set of interaction signals." — [TAI-CHI / Time reversal interactive objects (ResearchGate)](https://www.researchgate.net/publication/252367235_Time_reversal_interactive_objects); [TAI-CHI overview (ResearchGate)](https://www.researchgate.net/publication/229039711_TAI-CHI_Tangible_Acoustic_Interfaces_for_Computer-Human_Interaction)
- **Origin paper.** Ing, Quieffin, Catheline & Fink, "In solid localization of finger impacts using acoustic time-reversal process," *Appl. Phys. Lett.* 87, 204104 (2005). It is described as "at the origin of the first commercial application of time reversal in the field of acoustic interactivity" and became Sensitive Object technology. — [Catheline faculty page (LabTAU Lyon)](http://labtau.univ-lyon1.fr/members/catheline-stefan); citation also in [Sensors 2013 time-reversal impact paper](https://doi.org/10.3390/s131013356)
- **Earlier work.** Ing, Quieffin, Catheline & Fink, "Sensor systems for interactive surfaces," *IBM Systems Journal* 39 (2000), is cited as earlier LTM work. — [koreascience LTM study](https://koreascience.kr/article/CFKO201431749163690.pdf)
- **Follow-on work.** Ing's group combined time-reversal impact localization with haptic feedback for touch panels. — [JASA 129(3):1297](https://pubs.aip.org/asa/jasa/article-abstract/129/3/1297/978117/Impact-localization-combined-with-haptic-feedback?redirectedFrom=fulltext)
- **TAI-CHI methods.** The EU TAI-CHI project studied three passive localization methods: TDOA (multi-sensor), time reversal / LTM (pre-recorded templates) and acoustic holography (ICP accelerometers in a line on a wooden table). Materials included wood boards, window glass, plastic blocks and metal sheets. — [TAI-CHI overview](https://www.researchgate.net/publication/229039711_TAI-CHI_Tangible_Acoustic_Interfaces_for_Computer-Human_Interaction); [Tai-Chi press summary](https://thefutureofthings.com/3420-tai-chi-future-interactive-interface/)
- **TAI-CHI object recognition.** A TAI-CHI-derived study (Politecnico di Milano) used a board with four accelerometers to recognize which object struck it. Accuracy was 73–100% depending on the object, signal quality and optional classification filtering. It also states that real-time localization of impulsive and continuous touches is possible on plexiglass and MDF. — [Audio-based object recognition for TAIs (Sarti, IEEE HAVE 2009)](https://sarti.faculty.polimi.it/Augusto_Sarti/CV_and_publications_files/2009_IEEE_HAVE_object_recognition_tangible_acoustic_interfaces.pdf)
- **Pham et al. (TAI-CHI chapter).** It compares TDOA and LTM experimentally and reports potential for real-time impact localization on common solid surfaces. No accuracy figure was visible in the snippet. — [Impact Localisation Techniques for TAIs (O'Reilly/Elsevier IPROMS 2006)](https://www.oreilly.com/library/view/intelligent-production-machines/9780080447308/ch81.html)
- **Cardiff PhD thesis (Ze Ji, TAI-CHI).** It ran experiments on LTM consistency, acquisition configuration and recognition accuracy. It also developed a maximum-likelihood estimator to improve the accuracy and reliability of acoustic localization. — [Development of TAIs for HCI, Cardiff ORCA](https://orca.cardiff.ac.uk/54576)
- **Elo Acoustic Pulse Recognition (APR), commercial.** Piezo transducers bonded to the edges of the glass pick up the touch sound. The controller digitizes it and compares it against "a list of prerecorded sounds for every position on the glass". This table lookup avoids expensive DSP hardware. — [Elo support: how APR works](https://elosupport.elotouch.com/hc/en-us/articles/31650748698903-How-does-APR-technology-work); [KioskMarketplace on Elo APR](https://www.kioskmarketplace.com/news/inside-elos-new-apr-touchscreen-technology-2)
- **Elo APR specs and status.** Rated operating range is –20 °C to 60 °C. Elo retired Pulse Touch/APR in 2012. — [Elo APR datasheet](https://www.touchwindow.com/mm5/graphics/00000001/elo/apr_ds.pdf); [Elo support](https://elosupport.elotouch.com/hc/en-us/articles/31650748698903-How-does-APR-technology-work)

### Inferences
- **Why one sensor works.** A finite plate with reflections makes each source point's impulse response near-unique (the reverberant wavefield). The single-sensor capability depends on the plate being reverberant and stable, not on sensor geometry.
- **Lid resolution.** If resolution is about half the dominant wavelength, a finger tap on 0.5–1 mm aluminium (bending waves of tens of cm wavelength at a few hundred Hz to a few kHz) should resolve coarse zones (corners, edges, centre: about 4–9 zones), not fine positions. This is a physics-based estimate, not a measured result.
- **Calibration burden.** Elo APR and Sensitive Object calibrate a fixed panel at the factory. A MacBook-lid app would need a per-user (or per-model) enrolment of maybe 10–30 taps per zone, similar to Knocker's "20 training knocks" (Q3).

### Gaps
- I could not access the full text of Ing et al. 2005 (APL) or the TAI-CHI final reports. I found no verified numeric localization resolution or accuracy (e.g., "x mm on glass") for single-sensor LTM.
- I found no source on how Elo APR or Sensitive Object handled temperature drift, water or objects resting on the glass, beyond the datasheet operating range.

## Q2. TDOA methods: why they need spacing and high sample rates, and can laptop mics do it?

### Takeaway
TDOA systems (Paradiso's interactive window, Toffee, ALTo, MM-Tap) need several sensors spread over tens of centimetres and well-resolved onsets. Bending waves in plates are dispersive and fast (hundreds of m/s), so a few cm of position maps to tens of microseconds. That pushes sample rates toward 96–192 kHz and requires good sensor coupling. Results range from about 1.5–3 cm on large boards (ALTo) to bearing-only estimates (Toffee, 4.3° mean error). Laptop mics are air-coupled, sit in the base, are a few cm apart and run at 48 kHz, so full TDOA on the lid is very unlikely. Coarse left/right or bearing cues remain plausible.

### Cited Findings
- **Paradiso / MIT Responsive Environments interactive window.** Four contact piezo pickups sit near the corners of a glass sheet. A DSP extracts signal features and estimates hit location from timing differences, plus a rough per-hit accuracy estimate. "Knuckle taps are low-frequency impulses that vary considerably hit-to-hit, and the bending waves propagating through the glass are highly dispersive." — [MIT Media Lab publication page](https://www.media.mit.edu/publications/passive-acoustic-knock-tracking-for-interactive-windows-2); [Tapper project page](https://resenv.media.mit.edu/Tapper/); [SIGGRAPH history: The Interactive Window](https://history.siggraph.org/?p=53990). The full PDF with error figures (Paradiso & Leo, "Tracking and Characterizing Knocks Atop Large Interactive Displays," *Sensor Review* 2005) refused the connection. Exact cm figures are in the Gaps.
- **Toffee (Xiao, Lew, Marsanico, Hariharan, Hudson, Harrison; MobileHCI 2014).** It uses acoustic time-difference-of-arrival with sensors in the device to extend touch onto the tabletop the device rests on. Mean bearing error was 4.3° with a laptop prototype. It needs a hard tabletop, with gravity providing the acoustic coupling. It reports bearing (angle), which enables "radial" virtual buttons, not full x/y. — [Toffee project page](https://chrisharrison.net/index.php/Research/Toffee); [dblp](https://dblp.dagstuhl.de/rec/conf/mhci/XiaoLMHHH14.html). Press coverage describes microphones at each corner of a tablet. — [Softpedia](https://news.softpedia.com/news/Tablets-with-Sonic-Sensors-Will-Let-You-Control-Your-Device-via-Table-Tabs-and-Swipes-460966.shtml)
- **ALTo (2021, arXiv).** It uses four piezo disks, 26 cm from the origin on each axis, through two stereo inputs on a wooden board. Moving from 44.1 kHz to 192 kHz "significantly reduced the variability of the readings." Measured wave speed was 450 m/s in x and 373 m/s in y, so the board is anisotropic. Mean absolute error was 1.45 cm (x) and 2.72 cm (y), with taps every 10 cm. Stated error sources: amplitude-threshold onset detection varies with tap loudness, propagation is non-uniform (systematic y bias), and metal table supports and warped wood change results. — [ALTo, ar5iv](https://ar5iv.labs.arxiv.org/html/2108.06837)
- **ALTo on natural sounds.** It notes that natural sounds such as taps are harder to localize accurately than emitted ultrasonic signals. — [ALTo](https://ar5iv.labs.arxiv.org/html/2108.06837)
- **MM-Tap.** It pushes vibration-based tap localization "from unstable cm-level to mm-level" using TDOA. It notes that fluctuating wave velocity is the core problem for TDOA triangulation. — [MM-Tap (ResearchGate)](https://www.researchgate.net/publication/371468058_MM-Tap_Adaptive_and_Scalable_Tap_Localization_on_Ubiquitous_Surfaces_with_mm-level_Accuracy)
- **Table with emitted pulses (active, for contrast).** Four microphones gave about 3 cm average accuracy on a 1 × 2 m table, using barely audible emitted pulses rather than taps. — [Kreskowski et al. 2015, TUM](https://www.campar.in.tum.de/pub/kreskowski2015mobat/kreskowski2015mobat.pdf)
- **Acustico (wrist-worn sensors).** RMS errors were 7.6 mm (X) and 4.6 mm (Y) across surfaces, with sensors on the wrist rather than the surface. — cited in the search summary of [paper.nweon.com](https://paper.nweon.com/8490). This is a secondary aggregator, so verify before relying on it.
- **Hobbyist TapTDOA.** It shows that piezo TDOA works on hard surfaces with cheap hardware. — [hackaday.io TapTDOA](https://hackaday.io/project/159821-taptdoa)

### Inferences
- **Why sample rate matters.** At about 400 m/s, 1 cm equals 25 µs. One sample at 48 kHz (20.8 µs) is roughly 1 cm of path difference, before dispersion smearing. With mics only a few cm apart, the usable delay range is just a few samples. Sub-sample interpolation helps but dispersion and onset ambiguity dominate (Paradiso, ALTo).
- **MacBook geometry.** The built-in mics are in the base or around the keyboard/display bezel and couple mainly through air. Lid vibration reaches the base IMU only through the hinge. Lid-tap TDOA would therefore be confounded by hinge transmission and airborne paths. A Toffee-style left-vs-right bearing cue from the stereo or array mics is the most a TDOA approach could plausibly add.
- **Practical recommendation.** Treat TDOA and inter-mic level differences as features fed to an ML/template classifier, not as a geometric solver.

### Gaps
- I could not retrieve Paradiso & Leo's quantitative error (cm sigma) or their sample rate. The MIT PDF host refused the connection.
- I could not verify Toffee's sensor count, sample rate or distance accuracy from the full paper. The project page gives only the 4.3° bearing error.
- I found no paper that attempts TDOA tap localization using a laptop's own built-in microphones on its own chassis.

## Q3. ML-based tap/knock classification with phone and laptop built-in sensors

### Takeaway
The phone motion-sensor side-channel literature is the closest analogue: a built-in IMU inferring where a tap landed on the same rigid device. TapPrints reached up to about 90% (phones) and 80% (tablet) for tap location and letters. TouchLogger got 71.5% of keystrokes from accelerometer orientation. Field data costs about 20 points versus lab (TapSensing). Acoustic ML on built-in or attached mics classifies tap types, objects and gestures at 90–99% in the lab, with clear drops in noisy or real-world settings (Knocker: 98% lab vs 83% wild).

### Cited Findings
- **TapPrints (Miluzzo et al., MobiSys 2012).** It uses accelerometer and gyroscope on 2 smartphones and 1 tablet. It reached up to 90% (smartphones) and 80% (tablet) for identifying tap locations and inferring English letters. Contextual priors could improve it further. — [ACM DOI 10.1145/2307636.2307666 via SpringerProfessional](https://www.springerprofessional.de/doi/10.1145/2307636.2307666); [unpaywall](https://unpaywall.org/10.1145%2F2307636.2307666)
- **TapSensing follow-up (field study).** It used 27 participants and 3 iPhone models. Tap-location inference is "generally possible" from field data, but performance drops about 20% versus lab. Earlier results were from controlled taps. — summarized via search; the likely source is [Springer 10.1007/978-3-030-50309-3_43 (unpaywall)](https://unpaywall.org/10.1007%2F978-3-030-50309-3_43). I did not confirm the exact paper title.
- **TouchLogger (Cai & Chen, HotSec 2011).** It infers keystrokes from device orientation changes measured by motion sensors: "more than 70%" of keys, and 321/449 = 71.5% on the largest dataset (number-pad layout). — [TouchLogger paper (UC Davis)](https://www.cs.ucdavis.edu/~hchen/paper/hotsec2011.pdf); [slides](https://static.usenix.org/event/hotsec11/tech/slides/cai.pdf)
- **ACCessory (Owusu et al., HotMobile 2012).** It infers passwords from the accelerometer alone. 6-character passwords were recovered in a median of 4.5 trials. It notes the accelerometer needs no permission. — [ACCessory paper](https://ptolemy.berkeley.edu/projects/truststc/pubs/844/HotMobile12-final42-1.pdf)
- **Aviv et al. (ACSAC 2012).** Motion noise such as walking has a considerable effect on accelerometer side-channel accuracy. — [Practicality of Accelerometer Side Channels](https://www.cs.swarthmore.edu/~aviv/papers/aviv-acsac12-accel.pdf)
- **Later sensor-fusion work.** A later system reported 90.2% with accelerometer, gyroscope and magnetometer. A 2013 benchmark found the gyroscope the best single sensor for keystroke inference on Android. — [AlphaLogger (LJMU)](https://researchonline.ljmu.ac.uk/id/eprint/12198/1/AlphaLogger%20%283%29.pdf); [On the best sensor for keystrokes inference attack on Android](https://portal.arid.my/27/Publications/Details/124)
- **Knocker (Gong, Cho, Lee, Lee; KAIST; IMWUT/UbiComp 2019).** A phone knocks against an object and identifies the object using only built-in sensors. Because "using only sound is susceptible to noise," it fuses mic, accelerometer and gyroscope. Results:
  - about 98% in the lab and 83% in the wild (café or roadside), with 229 ms latency
  - 93% across 12 similar objects (books, bottles)
  - 92% across 23 everyday objects with only 20 training knocks per object
  - the CHI 2018 LBW version reached up to 99.7% on 14 objects

  Sources: [Knocker project page](https://nmsl.kaist.ac.kr/projects/knocker); [IMWUT'19 PDF](https://nmsl.kaist.ac.kr/pdf/IMWUT19_Knocker.pdf); [KAIST news](https://news.kaist.ac.kr/newsen/html/news/?mode=V&mng_no=6064)
- **TapSense (Harrison, Schwarz, Hudson; UIST 2011).** It classifies the sound of the finger part striking a surface (tip, pad, nail, knuckle). Four-class sets reached about 95%, and two-class sets (pen vs finger) over 99%. A standard phone mic is ill-suited because it is voice-optimized, so an inexpensive attached contact-type mic was used. Near-simultaneous impacts can fail to segment. It was commercialized as Qeexo FingerSense. — [FIGLab TapSense](https://www.figlab.com/research/2011/tapsense); [CMU news](https://www.cmu.edu/news/stories/archives/2011/october/oct19_tapsense.html); [HCI museum](https://hci-museum.lisn.upsaclay.fr/tapsense); [chrisharrison.net](https://chrisharrison.net/index.php/Research/TapSense)
- **Scratch Input (Harrison & Hudson, UIST 2008).** An acoustic (stethoscope-style) sensor picks up fingernail scratches on wood, fabric or paint. Six gestures reached about 90% accuracy (89.5%) with under 5 minutes of training, across a wide variety of surfaces, with 15 participants. — [Scratch Input project page](https://www.chrisharrison.net/index.php/Research/ScratchInput); [dblp](https://dblp.dagstuhl.de/rec/bibtex/conf/uist/HarrisonH08)
- **Taprint (MobiSys 2019).** It uses a commodity smart wristband IMU to recognize taps on the back of the hand as a keypad. It reached 96% keystroke recognition across 128 users and 2.4% authentication error from a single tap. It "overclocks" the IMU sampling rate via cubic-spline interpolation to extract fine features. This is sensing on-body rather than on a rigid plate. — [Taprint, ACM](https://dl.acm.org/doi/pdf/10.1145/3300061.3300124); [ResearchGate](https://www.researchgate.net/publication/334982629_Taprint_Secure_Text_Input_for_Commodity_Smart_Wristbands)
- **VibWrite (Rutgers; active, for contrast).** It uses one vibration motor and one receiver on any solid surface for finger-input authentication. It reached over 95% (later over 97%) within two trials with under 3% false positives. — [VibWrite PDF](https://www.winlab.rutgers.edu/~yychen/papers/vibwrite.pdf)

### Inferences
- **The direct analogue.** A built-in IMU and mic on the same rigid body inferring tap location among about 10–30 targets on a phone works at 70–90% in lab conditions. A MacBook lid has fewer, larger zones but a worse sensor path (IMU in the base, through the hinge).
- **Expected accuracy for 4–6 lid zones.** A target of 90%+ seems plausible with per-user enrolment (about 20 taps per zone, per Knocker). A realistic in-the-wild figure is roughly 15–20 points lower unless robustness is designed in.
- **Sensor fusion.** Fusing mic and IMU (as Knocker did) is the recommended route. The IMU is immune to airborne noise, and the mic carries more high-frequency, position-specific content.
- **Tap type matters.** TapSense shows tap type (nail vs pad vs knuckle) changes the acoustic signature strongly. A lid-zone classifier must either train on all tap types or detect type first.

### Gaps
- I did not verify the Ubicoustics, Acoustruments, SurfaceSight, BeyondTouch, ForcePhone, TapSkin or SonarSnoop numbers in this pass. SurfaceSight (LIDAR) and SonarSnoop (active sonar) are not passive vibration methods anyway.
- I found no "TapLoc" paper matching the brief in search results.
- The Knocker PDF was unreadable via fetch, so I lack its sampling rates and per-factor robustness ablations (knock force, user variation, grip).

## Q4. Keyboard acoustic eavesdropping: evidence that a laptop's mics can tell fine positions apart on the same device

### Takeaway
Laptop keystroke acoustic attacks show that audio can discriminate around 36 nearby positions on a laptop chassis at 93–95% per key (Harrison et al. 2023, MacBook Pro 13"). The recordings were made by a phone 17 cm away and over Zoom, not by the laptop's own internal mics on the lid. Classic work reached about 80% per key (Asonov & Agrawal 2004), with word-level recovery near 96% only after language modelling (Zhuang et al. 2005). These numbers rely on per-device, per-typist training.

### Cited Findings
- **Harrison, Toreini & Mehrnezhad 2023.** "A Practical Deep Learning-Based Acoustic Side Channel Attack on Keyboards" used a 13" MacBook Pro with 36 keys × 25 presses each. Results:
  - 95% accuracy, recorded by an iPhone 13 mini at 17 cm, with no language model
  - 93% when recorded via Zoom
  - mel-spectrogram images fed to the CoAtNet image classifier

  Sources: [arXiv 2308.01074](https://arxiv.org/abs/2308.01074v1); [Royal Holloway news](https://venue.royalholloway.ac.uk/about-us/news/study-suggests-ai-can-detect-your-password-from-the-sound-of-keys-being-pressed); [Gigazine summary](https://gigazine.net/gsc_news/en/20230807-acoustic-attack-steals-keystrokes)
- **Asonov & Agrawal (IEEE S&P 2004).** Neural nets trained on labelled sounds from the same user and keyboard reached about 80% per key. A later commentary calls some headline 2004 percentages "a little misleading." — [Keyboard Acoustic Emanations (PDF)](https://davidsalomon.name/CompSec/auxiliary/KybdEmanation.pdf); [Zhuang et al. TISSEC](https://people.eecs.berkeley.edu/~tygar/papers/Keyboard_Acoustic_Emanations_Revisited/TISSEC.pdf)
- **Zhuang, Zhou & Tygar (CCS 2005 / TISSEC 2009).** "Keyboard Acoustic Emanations Revisited" reached nearly 96% character recovery. It works without labelled training: clustering, then an HMM language model like a substitution cipher, then feedback-trained classifiers. Neural networks did worse than linear classification on its test sets. — [The Register 2005](https://www.theregister.com/2005/09/16/key_clicks_betray_passwords); [Zhuang paper (UT Austin mirror)](https://www.cs.utexas.edu/~shmat/courses/cs6431/zhuang.pdf); [TISSEC preprint](https://people.eecs.berkeley.edu/~tygar/papers/Keyboard_Acoustic_Emanations_Revisited/tiss.preprint.pdf)

### Inferences
- **What carries the signal.** Key position is discriminated mostly by how each key's impact excites the chassis and keyboard plate, not by geometric time delays. This is the same principle as LTM (Q1), but with learned features. It strongly supports a learned per-zone acoustic fingerprint approach on a lid.
- **Differences on a lid.**
  - Key clicks are mechanically consistent strikes. Finger taps on a lid vary more in force and contact type.
  - Key positions are a few cm apart, while lid zones would be 5–15 cm apart. That eases discrimination but adds the hinge path.
  - These attacks used external microphones, so the internal-mic path is unverified.

### Gaps
- I did not find (in this pass) a peer-reviewed study that uses a laptop's own built-in microphones to classify where its own chassis or lid was struck. Results for that exact setting are unknown.
- I did not verify any study using the MacBook's internal motion sensor for keystroke or tap inference.

## Q5. Robustness factors (grip/boundary conditions, temperature, resting surface, tap force, nail vs pad) and recalibration

### Takeaway
Robustness is the weak point of every passive approach. The most consistent failure modes reported are:
- changes in coupling and boundary conditions (resting surface, supports, warps, objects)
- variable tap force and onset amplitude
- tap type (nail, pad, knuckle)
- ambient noise for mic-based sensing, giving roughly 15–20 points lab-to-wild drops (Knocker, TapSensing)

Template methods (LTM, APR) need a stable plate. I found little published quantitative work on temperature drift or recalibration schedules.

### Cited Findings
- **Boundary conditions.** ALTo found localization reliability varies with surface acoustic properties. Metal table supports and warps in wood perturb results, and propagation is non-uniform and anisotropic (450 vs 373 m/s on one board). — [ALTo](https://ar5iv.labs.arxiv.org/html/2108.06837)
- **Tap force.** In ALTo, amplitude-threshold onset detection means variable loudness causes timing error. — [ALTo](https://ar5iv.labs.arxiv.org/html/2108.06837)
- **Hit-to-hit variability.** In Paradiso's window, knuckle taps "vary considerably hit-to-hit" and are low-frequency, and glass is dispersive. Their system reports a per-hit accuracy estimate to flag unreliable hits. — [MIT Media Lab](https://www.media.mit.edu/publications/passive-acoustic-knock-tracking-for-interactive-windows-2)
- **Fluctuating wave velocity.** MM-Tap names this as the core instability of vibration TDOA and addresses it adaptively. — [MM-Tap](https://www.researchgate.net/publication/371468058_MM-Tap_Adaptive_and_Scalable_Tap_Localization_on_Ubiquitous_Surfaces_with_mm-level_Accuracy)
- **Noise.** Knocker dropped from 98% (quiet lab) to 83% (café or roadside), the motivation for fusing the IMU. — [Knocker project](https://nmsl.kaist.ac.kr/projects/knocker); [KAIST news](https://news.kaist.ac.kr/newsen/html/news/?mode=V&mng_no=6064)
- **Lab vs field.** Field tap-location inference on iPhones lost about 20% versus lab. — [TapSensing via unpaywall](https://unpaywall.org/10.1007%2F978-3-030-50309-3_43)
- **Motion.** Walking and other motion considerably degrade accelerometer tap inference. — [Aviv et al. ACSAC 2012](https://www.cs.swarthmore.edu/~aviv/papers/aviv-acsac12-accel.pdf)
- **Tap type.** The finger part (tip, pad, nail, knuckle) produces acoustically distinct, classifiable signatures (about 95% across 4 classes). A zone classifier will see tap-type variation as a confound unless it is modelled. — [TapSense](https://www.figlab.com/research/2011/tapsense)
- **Coupling.** Toffee requires a hard tabletop, because gravity coupling between device and surface is what carries the signal. Coupling changes the channel. — [Toffee](https://chrisharrison.net/index.php/Research/Toffee)
- **Temperature.** Commercial LTM (Elo APR) was rated for –20 to 60 °C operation. No compensation method was published in what I found. — [Elo APR datasheet](https://www.touchwindow.com/mm5/graphics/00000001/elo/apr_ds.pdf)
- **Calibration effort.**
  - Scratch Input: under 5 minutes of training per user. — [Scratch Input](https://www.chrisharrison.net/index.php/Research/ScratchInput)
  - Knocker: 20 knocks per class. — [Knocker](https://nmsl.kaist.ac.kr/projects/knocker)
  - Harrison 2023: 25 presses per key. — [arXiv 2308.01074](https://arxiv.org/abs/2308.01074v1)
  - Zhuang 2005: an unsupervised route via a language model, with no labelled training. — [Zhuang TISSEC](https://people.eecs.berkeley.edu/~tygar/papers/Keyboard_Acoustic_Emanations_Revisited/TISSEC.pdf)
- **Field-robust fingerprinting (adjacent physics work).** It treats position sensing with wave fingerprints in dynamic, changing propagation environments as an open problem worth dedicated methods. — [Robust position sensing with wave fingerprints in dynamic complex propagation environments, Phys. Rev. Research 2, 043224](https://journals.aps.org/prresearch/abstract/10.1103/PhysRevResearch.2.043224)

### Inferences (what transfers to a MacBook lid: aluminium back, glass front, hinge, 1–3 mics, 1 base IMU)
- **Approach.** Use classification, not localization. LTM and keyboard-eavesdropping results show a learned per-zone fingerprint from one or two sensors is viable. TDOA is not viable with the mics' spacing, airborne coupling and 48 kHz rate. Target about 4–6 coarse zones (e.g., 4 corners plus centre, or left/centre/right), not continuous x/y.
- **Sensors.**
  - Fuse mic and IMU, Knocker-style. The IMU rejects acoustic noise.
  - The mics capture high-frequency, position-specific detail, plus left/right level and time cues if two or more mics exist.
  - The base IMU sees lid taps only through the hinge, which acts as a mechanical filter. Expect the IMU to be strongest for gross "tap occurred" detection and top-vs-bottom (hinge-distance) cues. That is an inference to test empirically.
- **Boundary conditions are the main threat.** The lid angle, the hinge torque state, the surface the MacBook rests on (desk vs lap vs soft surface), a hand holding the lid, and objects such as stickers or a case all change the modal response.
  - Train across lid angles and resting surfaces.
  - Consider lid-angle-conditioned models. Modern MacBooks have a lid-angle sensor, but its availability through APIs is unverified.
  - Add features that are invariant to coupling, such as normalized spectral shape.
- **Tap variation.**
  - Normalize amplitude and avoid amplitude-threshold onsets (ALTo's error source). Use energy or onset-detection with fixed alignment.
  - Train with soft and hard taps, and with pad, nail and knuckle taps, or add a tap-type head (TapSense).
- **Calibration.**
  - Budget about 20 taps per zone for enrolment (Knocker).
  - Add incremental, online re-enrolment from confident predictions to handle drift. No paper found quantified drift over days or temperature for these systems, so this is a design suggestion, not an evidence-based schedule.
- **Glass vs aluminium.** The glass front (display side) and aluminium back are bonded into one lid laminate, so taps on either face excite the same structure. Back taps (aluminium) are the likely use case. Their signature will differ from front-glass taps, so train both if both are allowed.
- **Expected numbers.** Lab-style accuracy of about 90–98% for 4–6 zones looks achievable by analogy (TapPrints, Knocker, keyboard attacks), dropping to about 75–85% in uncontrolled use unless robustness is engineered. This is extrapolated, not measured on a MacBook.

### Gaps
- I found no quantitative published study of temperature effects or long-term drift on LTM or tap-classification accuracy.
- I found no study on tap localization specifically on a laptop lid or display back, with any sensors.
- I could not confirm, from sources gathered here, whether MacBook built-in mics are in the lid or the base on current models, or how the base IMU (if accessible) can be read on macOS. The report writer should source these elsewhere.
- I did not verify a hinge-transmission or lid-angle effect on vibration signatures for laptops.
