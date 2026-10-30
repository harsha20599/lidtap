# Other built-in sensors, software tricks, and macOS integration for MacBook lid/display zone taps

Scope: every MacBook sensing channel except IMU and microphone vibration analysis (other researchers cover those), plus the macOS input layer, UX, and hardware-safety issues. No external hardware, no mirror. Research date: 2026-10-29.

## Q1. Built-in webcam without a mirror: can the FaceTime camera see where a finger is, and can camera ("where") be fused with vibration ("when")?

### Takeaway
The FaceTime camera faces outward, roughly in the plane of the display, so it cannot see the screen surface or the fingertip at the moment of contact. That is why Project Sistine needed a mirror. It can see the user's hand and arm as they reach toward the screen, though. Hand-pose models (Apple Vision, MediaPipe) could estimate a coarse target region, and vibration could supply the exact tap moment. This camera-for-where plus vibration-for-when pattern has prior art (a patent, STATINA, SurfaceXR). I found no project doing it on a laptop's own display.

### Cited Findings
- **Project Sistine (2018)** turned a MacBook into a touchscreen for about $1 of hardware. It was built in about 16 hours by Anish Athalye, Kevin Kwok, Guillermo Webster and Logan Engstrom, using a mirror angled in front of the built-in webcam "so that the webcam would be looking down at the computer screen at a sharp angle." — [Anish Athalye](https://anishathalye.com/macbook-touchscreen/); [9to5Mac](https://9to5mac.com/2018/04/08/touch-screen-mac-project/)
- **How Sistine detects touch.** It filters for skin colour, thresholds the image and finds contours. The finger and its reflection in the glossy screen are the two largest contours. A touch counts when the finger meets its reflection; hover versus touch comes from the vertical gap between the two contours. — [Anish Athalye](https://anishathalye.com/macbook-touchscreen/)
- **Sistine calibration.** The user touches prompted on-screen points. A webcam-to-screen homography is then fitted with RANSAC. Their camera was 480p. The authors say a flat mirror doesn't cover the whole screen and suggest a curved mirror and a higher-resolution camera. They report no latency or frame rate. — [Anish Athalye](https://anishathalye.com/macbook-touchscreen/)
- Sistine builds on **ShinyTouch**, which needed an external webcam. — [TechRadar](https://www.techradar.com/news/diy-project-can-give-your-macbook-a-touchscreen-for-just-dollar1); [Gizmodo](https://gizmodo.com/this-clever-macbook-touchscreen-hack-works-surprisingly-1825009539)
- **Apple Vision hand pose.** `VNDetectHumanHandPoseRequest` / `DetectHumanHandPoseRequest` is on macOS: revision 1 from macOS 11, the Swift `DetectHumanHandPoseRequest` from macOS 15. — [Apple docs (DetectHumanHandPoseRequest)](https://developer.apple.com/documentation/vision/detecthumanhandposerequest.md); [Apple docs (revision1)](https://developer.apple.com/tutorials/data/documentation/vision/vndetecthumanhandposerequestrevision1.md)
- Vision returns **21 landmarks per hand**, including fingertips. A secondary reference says `maximumHandCount` affects latency, so set it to 1. — [Axiom Vision reference (secondary)](https://skills.lc/tuliopc23/flying-dutchman-app/tuliopc23-flying-dutchman-app-claude-skills-axiom-vision-ref-skill-md)
- **Camera + vibration fusion: patent.** US9971457B2 flags a touch only when the camera sees a fingertip close to and moving toward the surface, and the microphone hears a vibration at the same time. — [Google Patents US9971457](https://patents.google.com/patent/US9971457)
- **Camera + vibration fusion: STATINA** (NTU Singapore, 2013). Cheap vibration sensors locate taps by time-of-arrival and a webcam tracks multiple fingers. Tested on wood, aluminium, steel, glass and plastic. — [Robaid](https://www.robaid.com/gadgets/statina-uses-vibration-to-enable-information-interaction-on-solid-flat-surfaces.htm); [optics.org](https://optics.org/news/4/7/46)
- **Camera + vibration fusion: SurfaceXR** (arXiv 2026). Fuses headset hand tracking with smartwatch-IMU micro-vibrations for surface touch. The authors note that hand tracking and plane estimation alone are too inaccurate to detect contact. Their end-to-end system reports median onset latency of 47 ms and offset latency of 170 ms. — [arXiv 2603.19529](https://arxiv.org/pdf/2603.19529)
- **Acustico** (UIST 2020) fuses surface waves and airborne sound to localise taps on uninstrumented surfaces. — [Unpaywall/ACM 10.1145/3379337.3415901](https://unpaywall.org/10.1145%2F3379337.3415901)
- **Camera privacy indicator.** Apple says the Mac camera "can't be activated without the camera indicator light also turning on." In 2013, Johns Hopkins researchers bypassed this only on older iSight firmware. — [Macworld](https://www.macworld.com/article/222599/eye-for-an-eye-researchers-foil-camera-indicator-light-on-some-macbooks.html); [MacRumors 2013](https://www.macrumors.com/2013/12/18/software-allows-hackers-to-activate-macbook-webcams-without-green-warning-light/)
- Users cannot turn the green light off, but can deny camera access per app in System Settings > Privacy & Security > Camera. — [SlashGear](https://www.slashgear.com/1951950/how-to-turn-off-green-dot-near-macbook-camera-what-it-means)
- **Apple's own camera input.** macOS Head Pointer (Accessibility > Pointer Control) moves the pointer from head movement seen by the built-in camera. It has been there since macOS 10.15.4. Optional "alternate pointer actions" map facial expressions (smile, open mouth, raised eyebrows) to clicks. — [thoughtbot](https://thoughtbot.com/blog/an-introduction-to-macos-head-pointer); [How-To Geek](https://www.howtogeek.com/788217/how-to-use-your-head-and-face-to-control-your-mac/); [AbilityNet (Sonoma)](https://mcmw.abilitynet.org.uk/how-to-control-your-computer-with-head-movement-in-macos-14-sonoma)
- Research shows head pointing is much slower and less accurate than a hand-held mouse, and camera tools are sensitive to lighting and user position. — [eScholarship paper](https://escholarship.org/content/qt26z6d0t4/qt26z6d0t4.pdf?t=sbtthu)

### Inferences
- **Geometry.** The camera sits in the top bezel and looks out along the screen normal, so a fingertip lying on the glass (depth ≈ 0) is outside its view. That is why Sistine needed a mirror. The camera does see the forearm, the back of the hand and the knuckles at a shallow angle while the hand is a few cm or more in front of the screen. Zones would therefore have to be extrapolated from the approach path and hand pose just before contact, not observed at contact.
- **Expected precision.** Probably good enough for left/centre/right, and maybe top/bottom when the arm is clearly visible: about 3–6 zones, not pixel accuracy. Two cues help: whether the arm enters from the left or right of the frame, and the hand's vertical position and size. A hand covering the camera (top-centre zone) is detectable from image darkening. This needs empirical validation.
- **Fusion design.** Vibration (IMU or mic, covered elsewhere) gives a sharp tap timestamp. The camera keeps a ring buffer of hand-pose estimates, and the system reads the pose from about 50–150 ms before the tap. This mirrors the patent and SurfaceXR logic. Vibration also rejects "hand near screen but no touch", which is the core weakness of camera-only systems.
- **Calibration.** A Sistine-style per-user step would show a zone target, record the hand pose and vibration features for each tap, then train a small classifier (kNN or logistic regression) instead of a homography, because there's no direct fingertip-to-screen mapping.
- **Costs.**
  - Continuous camera use keeps the green light on the whole time. Some users will find that unacceptable, and it raises privacy questions.
  - It costs power: camera plus Neural Engine/GPU inference at 15–30 fps.
  - Accuracy degrades in low light.
  - A practical compromise: turn the camera on only after the first vibration tap, or only in a "touch mode" the user toggles. On-demand activation loses the pre-tap approach frames, though.

### Gaps
- I found no measured frame rate or latency for Vision hand pose on Apple silicon with the FaceTime camera. It has to be benchmarked.
- I found no published project using an unmodified laptop webcam (no mirror) to localise touches on that laptop's own screen. The closest are Sistine (with mirror) and Head Pointer (no touch).
- "TouchCam" and Mudra (a wrist-worn neural-interface band, i.e. external hardware) weren't researched in depth. There were no tool calls left for them.
- No power-draw figures for continuous FaceTime camera use plus hand-pose inference.

## Q2. Ambient light / True Tone colour sensor: readable rate and hand-shadow detection

### Takeaway
On older Macs the ambient light sensor (ALS) can be read through the private IOKit `AppleLMUController` service. There's no public API, so the app can't be sandboxed. Sample code polls at 1–10 Hz, and Apple silicon or Touch Bar-era Macs often don't expose it the same way. A hand near the camera notch could shadow it, but that gives at most a coarse "top-centre zone" or "hand near" signal. It is too slow and too local for zone taps across the whole screen.

### Cited Findings
- **How it's read.** Code matches the `AppleLMUController` IOService, opens a connection and calls a method to read raw values. Chromium's macOS ambient light implementation also registered `IOServiceAddInterestNotification` (kIOGeneralInterest) on that service to learn when light conditions change. — [Chromium ambient_light_mac.cc](https://chromium.googlesource.com/chromium/src/+/c31119bc5/content/browser/device_sensors/ambient_light_mac.cc); [Chromium commit](https://chromium.googlesource.com/chromium/src.git/+/a5d055a1bd9e2db124cd7e2ef13c827f765f3c38)
- **Sample rates.** One lmutracker example uses `updateInterval = 1` (1 s polling). Another gist prints the value every 0.1 s. No documented sensor rate was found. — [gist (Glavin001)](https://gist.github.com/Glavin001/76ffcca87b946aa0b550f3ca46cbe146); [gist (kenji21)](https://gist.github.com/kenji21/29ac2f82dd246539d6c3)
- **Raw values aren't lux.** Hammerspoon notes that on Intel Macs raw data is converted to lux with a Firefox-derived algorithm that isn't guaranteed to be accurate. — [Hammerspoon libbrightness.m mirror](https://cdn05042023.gitlink.org.cn/dnrops/hammerspoon/src/branch/track-lua-threads/extensions/brightness/libbrightness.m); [Hammerspoon issue 1673](https://www.goodfirstissue.org/Hammerspoon/hammerspoon/issues/1673)
- **No supported API.** An Apple Developer Forums reply says there's no supported way to get the ambient light sensor value, and users report failures on Touch Bar MacBooks. — [Apple Developer Forums thread 96414](https://developer.apple.com/forums/thread/96414)
- Because the access is private, apps using it are distributed outside the Mac App Store. — [Lumen (GitHub)](https://github.com/knightfolk/Lumen)

### Inferences
- The ALS is a single point (or a few colour channels) next to the camera. It can only report shadowing near the top-centre of the lid, so it can't tell bottom-left from bottom-right.
- At 1–10 Hz with heavy internal smoothing (it's designed to drive auto-brightness), it can't time a tap. At best it's a slow "hand is near the top of the screen" prior.
- It's worse than the camera at the same job, since the camera covers the same area at 30–60 fps with spatial detail.
- On Apple silicon the ALS path may sit behind the sensor hub / HID event system rather than `AppleLMUController`, which makes access even less stable. This needs checking on target hardware.

### Gaps
- I found no source measuring the ALS's native sample rate or latency on Apple silicon MacBooks, or confirming the current access path (AppleLMUController versus an IOHIDEventSystem ALS service).
- I found no experiment on hand-shadow detection with the MacBook ALS.

## Q3. The display itself: capacitive coupling or panel effects measurable from software?

### Takeaway
None. Non-touch MacBook displays (LCD, mini-LED, and the non-touch M6 MacBook Pro) contain no touch digitiser, and I found no source showing a fingertip measurably perturbs any software-readable signal from the panel. Apple's first touch-sensing MacBook display is the new OLED MacBook Pro announced on 2026-10-28, which is new hardware and not a software trick.

### Cited Findings
- Apple announced the **MacBook Pro with "ProLED XDR" tandem-OLED touchscreen** at its 2026-10-28 "Pro and Tell" event:
  - 14-inch from $2,899, 16-inch from $3,399.
  - M5 Pro/Max chips.
  - Pre-orders opened 2026-10-28; ships 2026-11-06.
  - The touch screen adds about $400 over an equivalent non-touch model.
  - The M6 MacBook Pro ($1,999+) has no touch.

  — [CNBC](https://www.cnbc.com/2026/10/28/apple-mac-touchscreen-launch.html); [CNN Underscored](https://www.cnn.com/cnn-underscored/electronics/macbook-pro-oled-touchscreen-preorder); [Mac Observer](https://www.macobserver.com/news/touchscreen-macbook-pro-oled-price-release-date/); [Tom's Guide live blog](https://www.tomsguide.com/news/live/apple-touchscreen-macbook-pro-pro-and-tell-event-ipad-mini-8-imac-m6-live-updates)
- Before the event, reporting said the non-touch models would stay on sale. — [MacRumors](https://macrumors.com/2026/10/19/apple-october-28-product-launch/); [9to5Mac](https://9to5mac.com/2026/10/25/macbook-pro-redesign-oled-touch-launching-this-week/)

### Inferences
- With no digitiser, coupling into display drive electronics would be tiny. macOS doesn't expose panel electrical telemetry, timing-controller error counters or backlight current at any useful rate. Treat this channel as infeasible.
- The only "display-adjacent" software signal is the camera seeing the glossy screen's reflection, which is how Sistine worked. Without a mirror the camera can't see the screen.
- Product context: as of 2026-10-29 the software approach makes sense only for the large installed base of non-touch MacBooks. Apple now sells a native touch MacBook Pro at a premium.

### Gaps
- I found no source that explicitly tested and ruled out panel-electrical touch effects on MacBooks. The negative conclusion rests on there being no digitiser and no exposed telemetry, not on a published null result.
- Apple's own announcement or tech-specs page wasn't fetched. The details above come from press coverage on launch day.

## Q4. Trackpad (Force Touch / MultitouchSupport), Wi-Fi CSI, and Bluetooth RSSI

### Takeaway
A lid tap won't register on the trackpad. The private MultitouchSupport framework reports pressure only while something conductive (a finger) is in capacitive contact. Mechanical vibration through the chassis might nudge the force sensors, but the framework gates it out without a contact. macOS doesn't expose Wi-Fi channel state information (CSI): CoreWLAN gives only RSSI, noise and channel metadata, and needs Location permission. Fine-grained Wi-Fi finger sensing (WiFinger) needed a modified Intel 5300 Linux driver. RSSI/BLE at about 1 Hz is far too coarse for zone taps.

### Cited Findings
- **MultitouchSupport access.** Apps call `MTDeviceCreateList()` and `MTRegisterContactFrameCallback()` to get per-frame contact data from the trackpad. — [RWTH Aachen trackpad guide](https://hci.rwth-aachen.de/guide-trackpad)
- **TrackWeight.** It reads Force Touch pressure through the private framework, via a fork of OpenMultitouchSupport. It finds MultitouchSupport values "already in grams". It needs App Sandbox disabled and a Force Touch trackpad (2015+ MacBook Pro). — [TrackWeight (GitHub)](https://github.com/KrishKrosh/TrackWeight)
- **Contact required.** TrackWeight says pressure events come only when capacitance is detected, so a finger must stay on the pad. Metal objects may register as touches. — [TrackWeight (GitHub)](https://github.com/KrishKrosh/TrackWeight)
- **Public versus private.** Public APIs expose only high-level Force Click; raw force needs the private framework. Several struct fields are still unknown, and private-framework apps can't be sandboxed or sold on the Mac App Store. — [TouchBro](https://ithub.global.ssl.fastly.net/wlo2/TouchBro); [Ryan Hanson, Medium](https://medium.com/ryan-hanson/touching-apples-private-multitouch-framework-64f87611cfc9)
- **CoreWLAN.** It exposes channel properties (`wlanChannel`, `CWChannel`). Modern macOS limits Wi-Fi information without the Location privilege. — [Apple Developer Forums 813891](https://developer.apple.com/forums/thread/813891); [Apple CWInterface docs](https://developer.apple.com/documentation/corewlan/cwinterface.md)
- **Monitor-mode problems.** Channel switching in monitor mode is unreliable on recent Apple silicon models under macOS Tahoe. — [Kismet macOS CoreWLAN docs](https://kismetwireless.net/docs/readme/datasources/wifi-macos/); [Intuitibits](https://www.intuitibits.com/?p=3553)
- **WiFinger** (MobiHoc 2016) used CSI from a modified Intel 5300 driver and reached up to 90.4% accuracy on 9 ASL digit gestures. Users had to stay very still. — [WiFinger PDF](https://leehomcs.github.io/HongLi.github.io/papers/WiFinger.pdf); [The Register](https://www.theregister.com/2016/09/28/text_input_from_thin_air_boffins_give_wifi_the_finger_with_ai/)
- **Later CSI work** used a Dell laptop on Ubuntu with an Intel 5300 and a router sending 20 packets/s. — [arXiv 2106.00857](https://arxiv.org/pdf/2106.00857)

### Inferences
- **Trackpad.** A trackpad-based tap detector would only work if the user keeps one finger resting on the trackpad while tapping the lid with the other hand. That's awkward, but in principle the resting finger's force reading could carry the chassis impulse. It's an untested hack and not a natural UX.
- **Wi-Fi CSI.** Infeasible on macOS. Apple's Broadcom/Apple Wi-Fi stack offers no CSI extraction tool comparable to the Intel 5300, Atheros or Nexmon toolchains, and SIP/DriverKit block custom drivers.
- **RSSI and BLE.** The hand right next to the antennas (in the hinge or display) might shift RSSI. With roughly 1 Hz scan rates and multipath noise, that's at most a presence signal.

### Gaps
- No source states outright that macOS has no CSI API. The conclusion comes from CoreWLAN's documented surface and the absence of any macOS CSI tool in the literature.
- No experiment tested whether a lid tap changes trackpad force readings while a finger rests on the pad.
- Bluetooth RSSI proximity sensing on macOS wasn't specifically researched.

## Q5. Lid angle sensor, hinge, and hardware safety

### Takeaway
The lid angle sensor is readable from software: an undocumented HID feature report on Apple's Sensor Hub. It reports the hinge angle and could flag a firm tap that rocks the lid, but it can't localise the tap and is unreliable on some models. Hardware safety argues for light taps only. Apple community guidance warns against pressing the display or bezel, and pressure damage to MacBook panels is a known, usually unwarrantied, failure. I found no official Apple statement about repeated tapping.

### Cited Findings
- **Discovery.** Sam Henri Gold reverse-engineered the MacBook lid angle sensor (LidAngleSensor app; a creaky-door sound demo). It isn't a public API. — [Tom's Hardware](https://www.tomshardware.com/software/developer-tools/engineer-taps-into-apples-hidden-lidanglesensor-api-to-create-a-creaky-door-simulator); [heise](https://heise.de/-10650581); [Gigazine](https://gigazine.net/gsc_news/en/20250908-macbook-sensor-angle-screen-hinge)
- **HID details.** Vendor 0x05AC, Product 0x8104 (Sensor Hub), Usage Page 0x0020 (Sensor). Angle data comes via HID Feature Reports (Report ID 1), not Input Reports, so it must be polled. — [pybooklid (PyPI)](https://pypi.org/project/pybooklid/); [hinge-angle crate](https://docs.rs/crate/hinge-angle/0.1.0/source/src/macos.rs)
- **Model support.** One source says typically MacBook Pro 2019 onward; another says most 2016+ models. A German report says it doesn't work reliably on some models, especially M1. — [lid-angle-rs](https://rust-digger.code-maven.com/crates/lid-angle); [ifun.de](https://www.ifun.de/auch-zum-albern-gut-verborgener-displaywinkelsensor-im-macbook-264432/)
- **Apple Community on pressing.** Advice is to avoid pressing the glass bezel below the display, because the area beneath is largely hollow or holds flex cables, and to clean with the lid supported. — [Apple Community thread 254712427](https://discussions.apple.com/thread/254712427)
- **Pressure damage.** It ranges from marks to permanent panel damage, and accidental damage may not be covered by the standard warranty. This is from a repair forum, not Apple. — [app-elearn forum](https://www.app-elearn.com/forum/discussion/8734/macbook-screen-pressure-damage-can-it-be-fixed-without-replacing-the-panel)
- Many search results on "pressure damage MacBook" were SEO spam mirrors and were excluded.

### Inferences
- **Lid angle as a "when" channel.** A tap on the upper lid rocks it slightly against hinge friction. The angle sensor might show a sub-degree transient, but feature-report polling is slow and the sensor is likely quantised and filtered. It's at best a secondary confirmation of hard taps, and it can't tell zones apart (except perhaps top versus bottom, by deflection size). The IMU and mic channels are better.
- **Safety recommendation.**
  - Design for light fingertip taps on the active display area, not the bottom bezel.
  - Never ask users to "tap harder" to improve detection.
  - Brace the lid, or prefer taps near the top/side edges where the frame is stiffest.
  - Mini-LED and LCD panels can show pressure mura and backlight damage.
  - Oil and fingerprints on matte, anti-reflective or nano-texture glass need care when cleaning: use Apple's recommended methods only.
  - Repeated torque on the hinge from top-edge taps adds wear. The magnitude is unknown.
- **The new touch MacBook Pro** shows Apple considers touch on its tandem-OLED panel acceptable. That says nothing about older LCD/mini-LED lids, which weren't designed for it.

### Gaps
- I found no official Apple support article specifically about pressing or tapping MacBook displays (the fetch budget ran out before Apple's "How to clean your Apple products" page). The safety guidance above rests on community and repair sources.
- No source gives the lid angle sensor's sampling rate, resolution or noise floor.
- No quantitative data on hinge wear from repeated taps.

## Q6. macOS integration: turning zone taps into input (CGEvent, permissions, BTT/Hammerspoon/Karabiner, menu-bar app, calibration, overlay, latency)

### Takeaway
The integration layer is well-trodden. A non-sandboxed menu-bar app classifies taps, then either posts synthetic events with `CGEventPost` (this needs the user to approve the app under Privacy & Security > Accessibility; there's a preflight/request API), or hands off to BetterTouchTool via its `btt://` URL scheme or to Hammerspoon via `hs.urlevent` / Lua. Because the app also uses private frameworks (sensors) and posts events, it can't ship on the Mac App Store.

### Cited Findings
- **Permission.** `CGEventPost` needs no entitlement but does need user approval in System Settings > Privacy & Security. `CGPreflightPostEventAccess` / `CGRequestPostEventAccess` check and request it. If you just post, the system shows the TCC alert itself (Apple DTS). — [Apple Developer Forums 724603](https://developer.apple.com/forums/thread/724603); [Apple Developer Forums 744492](https://developer.apple.com/forums/thread/744492)
- **Sandbox.** A sandboxed app can't post events to control other apps. A clipboard manager was rejected under guideline 2.4.5 for using `CGEvent.post`. — [Apple Developer Forums 789896](https://developer.apple.com/forums/thread/789896); [Apple Developer Forums 820594](https://developer.apple.com/forums/thread/820594)
- **Known quirk.** One developer reports `CGPreflightPostEventAccess` doesn't update while the process is running, so relaunching after the grant may be needed (anecdotal). — [Apple Developer Forums 103992](https://developer.apple.com/forums/thread/103992)
- **Why the gate exists.** Patrick Wardle documented malware using synthetic clicks to dismiss security prompts, which is why macOS gates them. — [Objective-See "Synthetic Reality"](https://objective-see.org/blog/blog_0x36.html)
- **BetterTouchTool.** `btt://trigger_named/?trigger_name=…` runs a named trigger configured in BTT's "Other" tab. BTT also offers AppleScript, a built-in webserver, and an async no-response variant for non-blocking calls. — [BTT URL scheme docs](https://docs.folivora.ai/docs/scripting/url-scheme/); [BTT AppleScript docs](https://docs.folivora.ai/docs/scripting/apple-script/)
- **Hammerspoon.**
  - `hs.eventtap` can synthesise mouse/keyboard events (left button 0, right button 1, `rightClick` helpers) and watch events.
  - `hs.urlevent` lets external apps call `hammerspoon://…` URLs into Lua handlers, but can't return data to the caller.
  - `hs.urlevent.openURL` can call other apps' schemes.

  — [hs.eventtap docs](https://www.hammerspoon.org/docs/hs.eventtap); [hs.urlevent docs](https://www.hammerspoon.org/docs/hs.urlevent.html)
- **Private-API distribution.** Apps using private sensor frameworks (MultitouchSupport, ALS, lid sensor) must be distributed outside the Mac App Store. — [TrackWeight](https://github.com/KrishKrosh/TrackWeight); [Lumen](https://github.com/knightfolk/Lumen)
- **Head Pointer as a UX precedent.** The pointer can follow the head relatively or move when the head faces the screen edges ("edge" mode), and facial gestures can be bound to click actions. — [thoughtbot](https://thoughtbot.com/blog/an-introduction-to-macos-head-pointer); [How-To Geek](https://www.howtogeek.com/788217/how-to-use-your-head-and-face-to-control-your-mac/)

### Inferences (proposed architecture and UX, not cited fact)
- **Architecture.**
  - A Swift `NSStatusItem` menu-bar app (LSUIElement), non-sandboxed, notarised, and distributed directly.
  - A sensor-ingest thread (IMU/mic from other workstreams; optional camera via AVCaptureSession plus Vision) feeds a tap detector and then a zone classifier, which emits `ZoneTap(zone, confidence, t)`.
  - An action dispatcher maps zones to one of three backends:
    - (a) native `CGEvent` (key combos such as Ctrl-Up for Mission Control, media keys via `NSEvent.otherEvent` system-defined events, `CGEventCreateScrollWheelEvent` for scrolling);
    - (b) `btt://trigger_named` URLs, so power users set up actions in BTT;
    - (c) `hammerspoon://zoneTap?zone=N`, handled by Lua in `init.lua`.
  - Karabiner-Elements works on key remapping, so the cleanest bridge is to emit an unused key combo (F13–F20) that Karabiner or BTT then maps.
- **Zone-to-action mapping.**
  - Use few, large zones (e.g. a 2×3 grid or left/centre/right edges), sized to the classifier's confirmed accuracy.
  - Bind them to coarse, forgiving, idempotent actions: Mission Control, next/previous desktop, play/pause, volume, scroll page up/down, app switcher.
  - Avoid precise or destructive actions: no "click at fingertip location" unless accuracy is proven, and no close or delete.
  - Optionally require a double tap to arm, to cut false positives from typing or bumping the desk.
- **Calibration UI.**
  - A full-screen transparent `NSWindow` (borderless, `.screenSaver` level, ignoresMouseEvents) flashes one zone target at a time and asks for N taps per zone (about 5–10), recording features to train a per-device and per-user classifier.
  - Run a held-out check afterwards to show accuracy per zone, and auto-merge zones that get confused with each other.
  - Re-run calibration when the lid angle changes a lot (the lid sensor can trigger this) or the Mac moves to a different surface: desk versus lap changes vibration signatures.
- **Feedback overlay.** A brief (150–250 ms) translucent highlight of the detected zone, plus an optional haptic tick via `NSHapticFeedbackManager`, which only fires on the Force Touch trackpad when a finger is on it. An undo affordance helps with misfires.
- **Latency.** Vibration detection plus classification should take tens of ms. A camera adds a frame or two (33–66 ms at 30 fps) plus inference. Total under 150 ms feels responsive for discrete commands. SurfaceXR's measured 47 ms median onset is a reference point for a fused system.
- **Off-switch.** Provide a pause hotkey and auto-pause while typing, i.e. when keyboard events happened in the last ~300 ms. An `hs.eventtap`-style CGEventTap listen-only watch on key events needs Input Monitoring permission.

### Gaps
- I found no published latency measurement for `CGEventPost` round trips, or for BTT/Hammerspoon URL dispatch. (Anecdotally a few ms; unmeasured here.)
- The Karabiner-Elements integration specifics (virtual HID device, `karabiner_cli`) weren't fetched.
- No search was run on the macOS APIs for Mission Control or media-key posting. The API names above come from general knowledge and need verifying against Apple docs.

## Q7. Existing products and projects attempting a "touchscreen MacBook" in software, and lessons

### Takeaway
Every working "touch Mac" before October 2026 used either extra optics or hardware: Sistine (mirror), ShinyTouch (external webcam), and AirBar (an IR light bar, hardware). Apple's own camera-based input, Head Pointer, deliberately avoids touch. The lessons: camera-only touch needs a view of the screen plane; fusing contact confirmation from a second modality is the established fix; and coarse, forgiving actions beat pixel pointing. Apple's 2026-10-28 touch MacBook Pro now sets a native baseline that software approaches won't match on precision.

### Cited Findings
- **Sistine:** mirror plus webcam, 480p, homography calibration. The authors call it a proof of concept. — [Anish Athalye](https://anishathalye.com/macbook-touchscreen/)
- **ShinyTouch:** the external-webcam predecessor. — [TechRadar](https://www.techradar.com/news/diy-project-can-give-your-macbook-a-touchscreen-for-just-dollar1)
- **Head Pointer:** built-in camera head pointing plus facial-expression clicks, slower and less precise than a mouse. — [thoughtbot](https://thoughtbot.com/blog/an-introduction-to-macos-head-pointer); [eScholarship](https://escholarship.org/content/qt26z6d0t4/qt26z6d0t4.pdf?t=sbtthu)
- **Fusion projects:** STATINA, the US9971457 patent and SurfaceXR all add a second modality to confirm contact because vision alone misjudges touch. — [optics.org](https://optics.org/news/4/7/46); [Google Patents](https://patents.google.com/patent/US9971457); [arXiv 2603.19529](https://arxiv.org/pdf/2603.19529)
- **Native baseline:** Apple's touch OLED MacBook Pro (announced 2026-10-28, ships 2026-11-06). — [CNBC](https://www.cnbc.com/2026/10/28/apple-mac-touchscreen-launch.html); [Mac Observer](https://www.macobserver.com/news/touchscreen-macbook-pro-oled-price-release-date/)

### Inferences
- The realistic niche is "gesture hotkeys by tapping the lid" (coarse zones mapped to commands) for existing non-touch MacBooks, not a full touchscreen emulation.
- Of the software-only extras, the camera is the only one that plausibly adds spatial information. ALS, the lid angle sensor, the trackpad, Wi-Fi and Bluetooth add little or nothing for zone discrimination.
- Recommended ranking of channels beyond IMU and mic:
  1. Camera hand pose: an optional "where" prior, with privacy and power costs.
  2. Lid angle: possible confirmation of a hard tap only.
  3. ALS: a crude top-centre shadow cue.
  4. Trackpad, display electrical effects, Wi-Fi CSI, Bluetooth: infeasible or impractical.

### Gaps
- AirBar (Neonode IR bar), "Hand Mirror" (a camera-preview utility, not a hand-tracking input), Mudra and TouchCam weren't researched in this pass. Specs and claims for them are unverified here.
- I found no Touch Bar emulator projects relevant to lid taps. Not searched.
