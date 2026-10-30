# Reading the Apple Silicon MacBook IMU and lid-angle sensor to detect lid taps

Method note: besides web sources, I cloned and read the source of yamete, olvvier/apple-silicon-accelerometer, LidAngleSensor and MacDuo. I also ran a small ctypes probe that I wrote myself on the user's own machine, a **Mac15,12 (MacBook Air 13" M3, 2024) running macOS 27.0.1 (sw_vers build string "26A434")**, on 2026-10-29. Results from that probe are labeled "[local probe]". There's no URL for them because they're first-hand measurements; the probe script is at `tools/imu_probe.py`.

## Q1. Which models have the IMU, where it sits, and its rate, range, resolution and noise

### Takeaway
A Bosch 6-axis IMU (accelerometer plus gyroscope) is present on Apple Silicon laptops from the M2 generation on, and on the M1 Pro/Max MacBook Pros. It's absent on the M1 Air, the 13" M1 MacBook Pro, desktops and Intel Macs. It sits on the logic board in the **base**, not in the lid. It streams natively at about 800 Hz (measured 794 Hz here on an M3 Air). The gyroscope has a quantization step of 0.061 °/s, consistent with a ±2000 °/s range. The idle accelerometer noise envelope is around 0.01–0.016 g.

### Cited Findings
- iFixit's M2 MacBook Air chip ID guide (Step 8) identifies a "Bosch Sensortec 6-axis MEMS accelerometer & gyroscope". It gives no part number or purpose. — [iFixit M2 Air Chip ID](https://www.ifixit.com/Guide/Macbook+Air+13-Inch+Liquid+Retina+2022+Chip+ID/151816)
- In 2022 the M2 MacBook Air was reported as "the first Apple Silicon Mac with a built-in accelerometer", found in the iFixit teardown. — [MacRumors 2022](https://www.macrumors.com/2022/07/22/m2-macbook-air-first-mac-with-accelerometer/)
- The specific part is "believed to be Bosch BMI286 based on teardowns". That is community inference, not confirmed. — [olvvier/apple-silicon-accelerometer README](https://github.com/olvvier/apple-silicon-accelerometer)
- An HN commenter (1e1a) saw two IMU entries on an M4 14" MBP, both identifying as BMI286. They turned out to be one IMU exposed as usage 3 (accel) and usage 9 (gyro), sharing a serial number. — [HN item 47084000](https://news.ycombinator.com/item?id=47084000)
- yamete's coverage claim: "Apple Silicon laptops (M2 and later, plus M1 Pro/Max)". The M1 MacBook Pro (2020), M1 Air, all desktops and all Intel Macs lack the sensor. — [yamete README / yamete-sensor lib.rs](https://github.com/chipcolate/yamete)
- olvvier lists M2/M3/M4/M5 as supported. It was tested only on an M3 Pro MBP running macOS 15.6.1, and is known not to work on the M1 MBP 2020 or the M4 Max Mac Studio. — [olvvier README](https://github.com/olvvier/apple-silicon-accelerometer)
- Native rate: yamete says "the hardware clamps to ~805 Hz", so asking for a 1000 µs interval yields the native rate. The system default is an 8000 µs ReportInterval (125 Hz). yamete measured 807 Hz as an ordinary user. — [yamete iokit.rs / CLAUDE.md](https://github.com/chipcolate/yamete)
- olvvier also reports about 800 Hz native, with a default software decimation of 8 giving about 100 Hz. — [olvvier README](https://github.com/olvvier/apple-silicon-accelerometer)
- Report format, decoded empirically (the HID descriptor is an opaque blob of 22 × 8-bit fields):

  | Offset | Size | Field |
  |---|---|---|
  | 0 | 2 | u16 LE sequence counter, +1 per report, wraps at 0xFFFF |
  | 2 | 4 | always zero |
  | 6 / 10 / 14 | 4 each | i32 LE X / Y / Z, IOFixed 16.16 (divide by 65536 to get g or °/s) |
  | 18 | 4 | die temperature in °C (Q16.16), not a timestamp: it is bit-identical between the accel and gyro devices |

  — [yamete report.rs](https://github.com/chipcolate/yamete)
- Idle noise per yamete on a Mac16,5 (M4 Pro 16" MBP): "the envelope alone reaches 0.0159 g at rest". Idle p99.9 of the high-passed envelope is 0.0128 g and the idle max is 0.0268 g. STA/LTA reaches 8.3 to 13 with the laptop untouched. A 0.005 g threshold sits around the idle 95th percentile, i.e. below the noise floor. — [yamete config.rs](https://github.com/chipcolate/yamete)
- HN commenter 1e1a reports "considerable noise even when the machine is still". — [HN item 47084000](https://news.ycombinator.com/item?id=47084000)
- [local probe] Mac15,12 M3 Air, macOS 27.0.1, 4 s idle capture with ReportInterval set to 1000 µs:
  - Rate: accel and gyro both at 793.9–794.0 Hz with zero sequence gaps.
  - Gyro: raw values are always multiples of 4000/65536 = **0.0610 °/s**, exactly 1 LSB of a 16-bit ±2000 °/s gyro (16.4 LSB/(°/s)). Sample-to-sample noise is about 0.06 °/s RMS (about 1 LSB). Peak-to-peak per axis was 1.8–4.4 °/s, and the per-axis std from a 3 s run was 0.2–1.5 °/s.
  - Accel: raw step is 1 (1/65536 g), so values are post-processed and calibrated rather than raw sensor LSBs. Sample-to-sample difference RMS is only about 0.00012–0.00017 g, while per-axis std is about 0.01 g and peak-to-peak is 0.016–0.022 g.
  - Die temperature: 41.3 °C.
  - Caveat: the machine's physical state (on a desk or lap, typing nearby) is unknown.
- Location: nothing places the IMU in the lid. iFixit lists it among logic-board components, and the logic board is in the base. — [iFixit M2 Air Chip ID](https://www.ifixit.com/Guide/Macbook+Air+13-Inch+Liquid+Retina+2022+Chip+ID/151816). The HN thread also does not resolve lid vs base. — [HN](https://news.ycombinator.com/item?id=47084000)
- On a Mac16,5, matching only on usage page and usage returns **two** devices for the accelerometer usage. The report size (22) disambiguates them. — [yamete iokit.rs](https://github.com/chipcolate/yamete)
- [local probe] The full SPU device list on the M3 Air:

  | Product | Usage page | Usage | Max report bytes |
  |---|---|---|---|
  | wakehint | 0xFF00 | 0xFF | 1 |
  | accel | 0xFF00 | 3 | 22 |
  | gyro | 0xFF00 | 9 | 22 |
  | las (lid angle) | 0x20 | 0x8A | 8 |
  | als | 0xFF00 | 4 | 122 |
  | cma | 0xFF0C | 1 | 5 |
  | devmotion6 | 0xFF0C | 5 | 108 |
  | als-temp | 0xFF00 | 5 | 14 |

  All have Transport "SPU" and a default ReportInterval of 8000.

### Inferences
- The accelerometer's sample-to-sample increments are about 100× smaller than its overall std. That suggests the delivered accel stream is heavily low-pass filtered inside the SPU or IMU, so its usable bandwidth is likely well below the 400 Hz Nyquist limit. Alternatively, the variance is dominated by sub-Hz desk or body motion. Short tap transients (a few ms) may be smeared, so test bandwidth with real taps before relying on high-frequency accel content. The gyro appears less filtered: its HF noise is about 1 LSB.
- With the IMU in the base, a fingertip tap on the lid reaches the sensor mostly as (a) rotational impulse about the hinge axis and (b) structure-borne vibration through the hinge. The hinge's friction and compliance will attenuate and low-pass the signal. That favors gyro-based detection of lid taps, which is consistent with yamete's finding in Q3.
- A 0.061 °/s gyro LSB with about 1 LSB of HF noise means small angular impulses are resolvable. Whether a light fingertip tap (much softer than a "slap") clears the 0.2–1.5 °/s idle std is unproven.
- "devmotion6" (108 bytes) and "cma" (page 0xFF0C) are probably Apple's fused device-motion outputs. They're unexplored by the OSS projects (inference from names only).

### Gaps
- No datasheet or official spec. I found no confirmed part number, accel full-scale range, or IMU placement photo for M3, M4 or M5 boards.
- No per-model list was verified beyond the projects' claims. No source covers M5 or "MacBook Neo" IMU presence; LidAngleSensor's compat list mentions a "MacBook Neo" only as lacking a lid angle sensor.
- The accel full-scale range is unknown, because accel values are rescaled and not raw-LSB quantized.
- No noise spectral density or bandwidth measurement exists publicly.

## Q2. How to access it: IOKit details, permissions, sandbox, macOS versions, code

### Takeaway
Enumerate the `AppleSPUHIDDevice` services and pick usage page 0xFF00, usage 3 (accel) or 9 (gyro), with MaxInputReportSize 22. First wake the matching `AppleSPUHIDDriver` services by setting `SensorPropertyReportingState=1`, `SensorPropertyPowerState=1` and `ReportInterval=1000` (µs). Then call `IOHIDDeviceCreate`, `IOHIDDeviceOpen`, and `IOHIDDeviceRegisterInputReportWithTimeStampCallback` on a run loop or dispatch queue. **Root is not required.** Access is gated by the **Input Monitoring** TCC grant (`IOHIDCheckAccess` / `IOHIDRequestAccess`). This was confirmed working on macOS 27.0.1 as a normal user.

### Cited Findings
- yamete is explicit: "Contrary to every published project that reads this sensor, **root is not required**. Those projects enforce `geteuid() == 0` themselves; macOS does not. What access *is* gated by is the Input Monitoring TCC grant." Verified "streaming at 807 Hz as an ordinary user with no entitlements". — [yamete iokit.rs / CLAUDE.md](https://github.com/chipcolate/yamete)
- yamete calls `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent=0)` and `IOHIDRequestAccess(0)`. "Input Monitoring gates *all* HID access on macOS, not just keyboards." — [yamete iokit.rs](https://github.com/chipcolate/yamete)
- yamete runs as a per-user LaunchAgent, not as root, because "a root daemon has no login session" in which to show the Input Monitoring consent prompt. The grant is tied to the signing identity: ad-hoc re-signs re-prompt. It requires macOS 13+. — [yamete README](https://github.com/chipcolate/yamete)
- The critical non-obvious step is waking the sensors: "The power and reporting state live on the **`AppleSPUHIDDriver`** service; setting the same keys on the `IOHIDDevice` via `IOHIDDeviceSetProperty` is silently ignored, and the result is that `IOHIDDeviceOpen` succeeds but the input report callback never fires even once. It must also happen *before* the device is opened." Setting these can fail depending on privilege, but sensors often stream anyway. — [yamete iokit.rs](https://github.com/chipcolate/yamete)
- olvvier does the same wake loop. It calls `IORegistryEntrySetCFProperty` on each `AppleSPUHIDDriver` with `SensorPropertyReportingState=1`, `SensorPropertyPowerState=1` and `ReportInterval=1000`. It then iterates `AppleSPUHIDDevice`, matching `PrimaryUsagePage`/`PrimaryUsage`, and calls `IOHIDDeviceCreate`, `IOHIDDeviceOpen(hid, 0)`, `IOHIDDeviceRegisterInputReportWithTimeStampCallback` and `IOHIDDeviceScheduleWithRunLoop`. The timestamp is `mach_absolute_time`. This is pure Python ctypes. — [olvvier macimu/_spu.py](https://github.com/olvvier/apple-silicon-accelerometer)
- olvvier documents sudo as required and raises PermissionError without root. Enumeration via `IMU.available()` / `device_info()` works without root. It's tested on macOS 15.6.1 and warns it "may break on future macos updates". — [olvvier README](https://github.com/olvvier/apple-silicon-accelerometer)
- On HN, 1e1a reads the IMU without root on an M4 running Sequoia, contradicting the sudo claim. — [HN item 47084000](https://news.ycombinator.com/item?id=47084000)
- taigrr/spank (Go, about 4.6k stars) checks `os.Geteuid() != 0` and needs sudo, by its own choice. It's ported from olvvier. — [spank AGENTS.md](https://raw.githubusercontent.com/taigrr/spank/HEAD/AGENTS.md); [search summary of spank](https://pkg.go.dev/github.com/taigrr/spank)
- yamete warns: "Never seize the device; that would steal reports from the system's own consumer." So open with options 0, not `kIOHIDOptionsTypeSeizeDevice`. — [yamete CLAUDE.md](https://github.com/chipcolate/yamete)
- Sequence-gap tracking: compare consecutive u16 counters to count dropped reports. — [yamete iokit.rs/report.rs](https://github.com/chipcolate/yamete)
- [local probe] On macOS 27.0.1 (M3 Air):
  - `IOHIDCheckAccess(0)` returned 0 (granted) for the hosting process.
  - Without root, `IOHIDDeviceOpen` returned kIOReturnSuccess for accel, gyro and las.
  - Setting ReportInterval to 1000 on `AppleSPUHIDDriver` gave about 794 Hz.
  - `ioreg -r -c AppleSPUHIDDevice` shows the `IOUserClientClass` as `IOHIDLibUserClient`.

### Inferences
- Minimal recipe (Swift/C equivalent of the Python):
  1. `IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSPUHIDDriver"))`, then call `IORegistryEntrySetCFProperty` for each of the three keys.
  2. `IOServiceMatching("AppleSPUHIDDevice")`. Filter `PrimaryUsagePage==0xFF00 && PrimaryUsage in {3,9} && MaxInputReportSize==22`.
  3. Call `IOHIDDeviceCreate(kCFAllocatorDefault, service)`, then `IOHIDDeviceOpen(dev, 0)`.
  4. Register the callback with a 64-byte or larger buffer, then `IOHIDDeviceSetDispatchQueue` + `IOHIDDeviceActivate` (yamete), or schedule on a run loop.
  5. Parse x/y/z as `int32 @6/10/14 / 65536.0`.

  An `IOHIDManager` with `{kIOHIDDeviceUsagePageKey: 0xFF00, kIOHIDDeviceUsageKey: 3}` should also work, as MacDuo does for the lid sensor. But it may return the duplicate device seen on Mac16,5, so filter by report size.
- App Sandbox: no source tested sandboxed access. The IOHIDLib user client on a vendor-page device plus `IORegistryEntrySetCFProperty` on a driver will very likely be blocked in a sandboxed (Mac App Store) app. Plan for a non-sandboxed, Developer-ID-signed app with an Input Monitoring prompt. This is unverified.
- Version history: it works on macOS 13+ (yamete), 15.6.1 (olvvier), Sequoia (HN), and 27.0.1 (local probe). No source reports breakage in macOS 26 (Tahoe) or 27. Because it's undocumented, any update can break it.

### Gaps
- No primary source on App Sandbox or hardened-runtime behavior, or on whether any entitlement (e.g. `com.apple.security.device.usb`) changes it.
- I didn't verify whether the `IORegistryEntrySetCFProperty` wake call actually succeeds for non-root users, or whether streaming worked because something else (e.g. a system daemon) had already woken the SPU. yamete notes the setters "can fail depending on privilege level and the sensor streams anyway". The local probe got 794 Hz, so the rate change effectively took hold here.
- Asahi Linux documentation on the SPU/AOP sensor hardware was not researched (tool budget).

## Q3. Open-source projects: what they learned, detection methods, false positives, rates

### Takeaway
The most rigorous project is **yamete** (Rust, Apache-2.0, 2026). It found that detecting a hit on the lid needs **gyroscope corroboration**: lid strikes torque the machine about the hinge, while desk bumps and typing mostly translate it. It also found that published thresholds sit below the real noise floor. The others (olvvier/macimu, spank and derivatives) use simple accel-magnitude thresholds with cooldowns. LidAngleSensor and MacDuo read only the lid angle.

### Cited Findings
- **yamete (chipcolate)** — [repo](https://github.com/chipcolate/yamete), source read at commit dated 2026-08-20:
  - **Pipeline:**
    - Five accel detectors: STA/LTA, CUSUM, kurtosis, peak/MAD and absolute high-passed magnitude. The high-pass is a 5 Hz gravity strip at an 805 Hz nominal rate.
    - STA windows are 5/15/40 ms and LTA is 0.5 s.
    - At least 2 of the 5 detectors must vote. Cooldown is 0.75 s and peak-hold is 6 ms.
    - Default thresholds: STA/LTA 15, CUSUM 200 (leak 0.95), kurtosis 1100, peak/MAD 25, high-pass 0.035 g.
  - **Gyro gate (on by default):** the hit counts if gyro peak/accel peak ≥ **175 (°/s)/g** OR gyro peak ≥ **15 °/s**, within a 30 ms backward-looking window.
  - **Key measured result:** "a desk bump peaks at 0.73 g where a hard slap is 0.52 g — the rejected impact is larger — while rotation goes the other way (≈15 °/s vs ≈48 °/s). Striking the lid applies a torque about the hinge; a knock through the desk mostly translates the machine." "Every negative peaks below 14.6 deg/s while hard slaps reach 16-81."
  - **Corpus:**
    - 40 annotated slaps plus 150 s of silent activity.
    - Slap peaks range from 0.04 g to 0.62 g.
    - Severity tiers: micro 0.04 g, medium 0.12 g, major 0.30 g.
    - A real slap trips a mean of 2.2 detectors.
  - **Measured idle vs slap scores:**

    | Statistic | Idle p99.9 | Slap median |
    |---|---|---|
    | High-passed envelope | 0.0128 | 0.050 |
    | STA/LTA | 7.5 | 12.5 |
    | Peak/MAD | 7.66 | 18.5 |

    Kurtosis and CUSUM don't separate idle from slaps.
  - **Sensitivity sweep:**

    | Slider | Slaps caught | False positives |
    |---|---|---|
    | 0.20 | 13/40 | 0 |
    | 0.50 (default) | 35/40 | 0 |
    | 0.65 | 39/40 | 7 |
    | 1.00 | 40/40 | 18 |

    Typing stays silent at the default. Lowering thresholds "let trackpad clicks accumulate votes … and cost a false positive".
- **olvvier/apple-silicon-accelerometer (macimu, Python)** — [repo](https://github.com/olvvier/apple-silicon-accelerometer):
  - Provides accel, gyro, lid angle and ALS (lux plus 4 spectral channels), plus Mahony AHRS orientation.
  - Example `peak_detect` threshold of 1.2 g. Example filters: a 10 Hz 4th-order high-pass and a 5 Hz low-pass at 100 Hz.
  - Includes experimental heartbeat (BCG) via a 0.8–3 Hz bandpass.
  - No published tap algorithm.
  - Uses an 8000-entry shared-memory ring buffer in a separate worker process.
- **taigrr/spank (Go)** — [AGENTS.md](https://raw.githubusercontent.com/taigrr/spank/HEAD/AGENTS.md):
  - Detection is ported from olvvier. Defaults: slap cooldown 750 ms, sensor poll 10 ms, max batch 200 samples, minimum amplitude 0.30.
  - Requires root (by its own check).
  - Derivatives: OpenSpank, SlapMac (paid, Swift, adds shake and anti-theft), PostHog MeepSlap, FreeSlapMac (root LaunchDaemon). — [search results summary incl. korben.info](https://korben.info/en/spank-give-macbook-spanking.html)
- **LidAngleSensor (Sam Henri Gold)** — [repo](https://github.com/samhenrigold/LidAngleSensor): matches VendorID 0x05AC, ProductID 0x8104, UsagePage 0x20, Usage 0x8A. Details in Q4.
- **MacDuo (DhananjayBhosale)** — [repo](https://github.com/DhananjayBhosale/MacDuo):
  - Uses `IOHIDManagerSetDeviceMatching({kIOHIDDeviceUsagePageKey:0x20, kIOHIDDeviceUsageKey:0x8A})`, then polls `IOHIDDeviceGetReport(Feature, ID 1)` on a dispatch timer at 30/60/120 Hz (power- and thermal-aware).
  - Treats the sensor as "integer-degree reports" and uses hysteresis for stillness.
  - Claims macOS 13+, MacBook Air M2+, and MBP 14/16 with M1 Pro/Max+. Tested on M4.
- HN discussion of the olvvier post covers its wide use (heartbeat, ideas like shake-to-undo) and Apple's likely purpose (Vehicle Motion Cues on Mac laptops, which excludes the M1 Air and 13" M1 MBP). Nobody discussed taps there. — [HN item 47084000](https://news.ycombinator.com/item?id=47084000)

### Inferences
- yamete's corpus targets *slaps* (0.04–0.62 g). A fingertip tap is likely at or below the 0.04 g "micro" tier and near the 0.035 g high-pass threshold, so tap detection will likely need lower thresholds with gyro-primary gating. It will also need a per-machine idle calibration, as yamete recommends: thresholds about 2× the idle maximum.
- yamete's 175 (°/s)/g ratio is a direct, reusable feature for telling "struck the lid" from "bumped the desk" or "typed".

### Gaps
- yamete's README does not list per-axis gyro signatures or tap location, and none of the projects tries tap localization.
- I did not read spank's detector source (only AGENTS.md).

## Q4. The lid-angle sensor: resolution, update rate, how to read it, high-frequency content

### Takeaway
The lid-angle sensor ("las") is a Hall-effect sensor in the hinge. It's exposed as HID Sensor page 0x20, usage 0x8A, with product ID 0x8104. It's read by polling Feature report ID 1, or via input reports. The angle is a 16-bit little-endian value in bytes 1–2, in **integer degrees**. Integer-degree quantization plus slow polling make it useless for tap transients. At most it can veto events where the lid actually moved.

### Cited Findings
- The lid angle sensor was introduced with the 2019 16" MacBook Pro. — [LidAngleSensor README](https://github.com/samhenrigold/LidAngleSensor). iFixit found a small sensor facing the left hinge, with a magnet in the hinge. — [MacRumors 2019](https://www.macrumors.com/2019/11/19/16-inch-macbook-pro-lid-angle-sensor/)
- LidAngleSensor reads it like this:
  - `IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, buf[8], &len)`, with `angle = buf[2]<<8 | buf[1]`.
  - It polls on a 1/30 s timer and applies smoothing factor 0.05 and a 0.5° movement threshold.
  - Probe strategy: UsagePage 0x20 + Usage 0x8A, and a fallback search for PID 0x8104 under vendor page 0xFF00.

  — [LidAngleSensor.swift / HardwareCompat.swift](https://github.com/samhenrigold/LidAngleSensor)
- Compatibility conflict:
  - LidAngleSensor's README says it "does not work on M1/M2 devices" and lists the M1 Air and M1/M2 Touch Bar MBPs as problematic.
  - Its newer HardwareCompat table lists M1 Pro/Max (MacBookPro18,x), M2 Pro/Max, M3/M4 MBPs and M2/M4 Airs as supported, with M3 Air "add when confirmed".
  - It says the MacBook Neo has no lid angle sensor.

  — [LidAngleSensor repo](https://github.com/samhenrigold/LidAngleSensor)
- MacDuo validates `bytes[0]==1` and an angle in 0...180, calls the sensor "integer-degree", and polls at 30/60/120 Hz. — [MacDuo FoldMath.swift / LidSensor.swift / LidStillness.swift](https://github.com/DhananjayBhosale/MacDuo)
- olvvier reads the lid via the input-report callback: `data[0]==1`, `angle = u16le(data[1:3]) & 0x1FF`. — [olvvier _spu.py](https://github.com/olvvier/apple-silicon-accelerometer)
- [local probe] On the M3 Air (Mac15,12, macOS 27.0.1):
  - The "las" device exists (page 0x20, usage 138, 8-byte input reports, ReportInterval 8000 µs) and opens without root.
  - Feature report ID 1 returned `[1, 132, 0]`, i.e. 132°, constant over about 78 polls in 4 s.
  - This confirms the M3 Air has the sensor, which LidAngleSensor's table had left unconfirmed.

### Inferences
- With 1° resolution, a tap would have to physically deflect the lid by ≥1° to register. A fingertip tap may occasionally cause a 1-count flicker if the angle sits on a quantization boundary. It carries no useful high-frequency content.
- Its value for a tap detector is context: the current lid angle sets the IMU-to-lid geometry and the projection of the hinge axis, and a changing angle rejects events that were really lid adjustments.

### Gaps
- No source states the sensor's internal update rate. The SPU ReportInterval of 8000 µs suggests reports at up to about 125 Hz, but that's unverified, and neither accuracy nor hysteresis is documented.

## Q5. Is a lid tap detectable, and can its position be distinguished?

### Takeaway
**Detection**: there's strong indirect evidence for strikes on the lid. yamete measured lid slaps producing 16–81 °/s of gyro rate versus under 14.6 °/s for desk bumps. Light fingertip taps are not documented, but by inference they should be visible in the gyro at about 0.06 °/s resolution. **Localization**: no MacBook-specific demo or experiment exists. Prior art on phones (TapPrints, 2012) inferred tap location from accel plus gyro with up to 90% accuracy, so coarse zones are plausible but unproven on a hinged lid with a base-mounted IMU.

### Cited Findings
- "A slap on the lid imparts angular rate about the hinge; typing, trackpad clicks and desk bumps largely produce linear acceleration without it. On the recorded corpus it is the *only* feature that separates a slap from a knock on the desk." — [yamete config.rs](https://github.com/chipcolate/yamete)
- Hard slaps reach 16–81 °/s and all negatives are under 14.6 °/s. A slap gives about 48 °/s versus about 15 °/s for a desk bump. — [yamete config.rs / CLAUDE.md](https://github.com/chipcolate/yamete)
- TapPrints (MobiSys 2012) inferred tap location on phone and tablet touchscreens from accelerometer plus gyroscope with machine learning. It reported up to 90% accuracy for tap location and 80% for English letters. — [TapPrints DOI via unpaywall](https://unpaywall.org/10.1145%2F2307636.2307666)
- A 2020 field study, "Predicting Tap Locations on Touch Screens in the Field", found inference still works outside the lab, with about 20% lower performance. — [search summary, unpaywall 10.1007/978-3-030-50309-3_43](https://unpaywall.org/10.1007%2F978-3-030-50309-3_43)
- Practicality of accelerometer side channels (ACSAC 2012) describes TapPrints as using combined gyro and accel data to infer tap events and locations. — [Aviv et al. PDF](https://www.cs.swarthmore.edu/~aviv/papers/aviv-acsac12-accel.pdf)

### Inferences
These are physics reasoning, not sourced.
- A tap normal to the lid surface at lateral offset *x* from the lid's centerline, and height *h* above the hinge, produces:
  - Torque about the hinge axis ∝ *h*: the dominant pitch impulse, stronger for taps near the top edge.
  - Torque about the axis normal to the lid, roughly yaw in the base frame when the lid is open about 110–130°, ∝ *x*. The sign flips left versus right, but it's resisted by hinge stiffness and the base's inertia and friction on the desk.
- Since the IMU is in the base, the lid rotation couples through the hinge. Expected cues for coarse zones:
  - Left vs right: the sign of the yaw/roll gyro component, plus the ratio of yaw to pitch.
  - Top vs bottom: pitch-rate magnitude per unit accel. Also possibly lid ringing frequency, though the lid's first bending mode may be low and accel bandwidth appears filtered.
- A 2–3 zone (L/C/R) or 2×2 classifier, calibrated per machine and per lid angle, is the realistic target. A per-session ML fit (as in TapPrints) on features like signed peak gyro x/y/z, the gyro/accel ratio, and early-window waveform shape would likely beat hand rules.
- Confounds:
  - Desk compliance vs lap use.
  - Lid angle, so rotate features into a hinge-aligned frame using the las angle.
  - Typing and trackpad, which mostly cause linear acceleration per yamete.
  - Hinge play.
  - Tap force variability, so normalize by the magnitude of the total angular impulse.

### Gaps
- No public experiment, blog or demo of tap *localization* on a MacBook lid using this IMU.
- No published per-axis gyro signatures for taps at different lid positions.
- The local probe captured only idle data; no taps were recorded. The next step is recording labeled taps per zone.

## Q6. Prior art: the Intel-era Sudden Motion Sensor (SmackBook, etc.)

### Takeaway
Intel and PowerBook laptops with hard drives had a Sudden Motion Sensor (SMS) accelerometer, built to park HDD heads. It was widely hacked in 2006 (SmackBook Pro: whack the side to switch desktops; MacSaber). It needed a firm hit to the chassis, and light taps on the screen reportedly didn't register. It was dropped with SSD-only machines from 2012 on.

### Cited Findings
- SmackBook Pro (2006, Erling Ellingsen) used the SMS to switch virtual desktops when you smacked the side of the laptop, with code published. — [TidBITS 2006](https://tidbits.com/2006/05/29/sudden-motion-sensor-hacks/); [Gigazine](https://www.gigazine.net/gsc_news/en/20060606_smackpad/)
- A MacRumors user reported that a light knock on the wrist rest or a tap on the screen won't register. — [MacRumors forum thread](https://forums.macrumors.com/threads/macbook-pro-tap-the-screen-instead-of-command-tab.203593)
- Apple: SMS detects strong vibrations, sudden position changes and acceleration. SSD/flash Macs don't use it. It can be toggled with `sudo pmset -a sms 0/1`. — [Apple HT201666](https://support.apple.com/en-us/HT201666)
- The SMS shipped from the 2005 PowerBook G4 through HDD Intel MacBooks, was used by MacSaber and space switching, and was removed starting with the 2012 Retina MBP. — [HN item 47084000 (future10se)](https://news.ycombinator.com/item?id=47084000)
- An early hardware-hacking writeup of the MacBook movement sensor exists. — [damieng.com 2006](https://damieng.com/blog/2006/hardware_hacking_macbook_movement_sensor/)

### Inferences
- The SMS was accel-only and low-rate. The modern IMU adds a gyro and about 800 Hz, which is exactly what yamete found necessary to reject non-lid impacts. So the modern hardware is materially better suited to lid-tap detection than SMS-era hacks.

### Gaps
- I didn't look up the SMS's sample rate or resolution, or whether any "Knock" app (for example the iPhone-to-Mac unlock app "Knock") used the SMS.

## Q7. Power and CPU cost of streaming at high rate

### Takeaway
At the native rate of about 805 Hz across both accel and gyro, reading costs about **3.15% of one core**, dominated by kernel transitions per report. Detection DSP adds only about 0.35%. ReportInterval is the main power knob.

### Cited Findings
- "Reading two HID devices at 805 Hz is ~3.15 % of a core; the entire five-detector ensemble, socket server and action layer add ~0.35 %. `report_interval_us` is the only knob that meaningfully changes power." — [yamete CLAUDE.md](https://github.com/chipcolate/yamete)
- "Each report costs a kernel transition, and at 805 Hz across two devices that is the daemon's single largest expense." — [yamete iokit.rs](https://github.com/chipcolate/yamete)
- An open CoreAudio output stream costs 4.2% of a core even when silent, so yamete opens audio on demand. Not IMU-related, but relevant to app design. — [yamete CLAUDE.md](https://github.com/chipcolate/yamete)
- MacDuo scales lid HID polling at 30/60/120 Hz by power, temperature and display state. — [MacDuo docs/DEVELOPMENT.md](https://github.com/DhananjayBhosale/MacDuo)

### Inferences
- A Python ctypes callback at 1.6 kHz total (accel plus gyro) will cost noticeably more than Rust or Swift. A production tap detector should be native, with a lock-free ring buffer (yamete uses rtrb).
- Possible strategies:
  - Run gyro-only at full rate.
  - Stream at 2–4 ms intervals (250–500 Hz). That's probably enough given the apparently low-pass-filtered accel, but the tap-timing impact is untested.
- SoC-level battery impact (SPU power-state changes) isn't measured anywhere.

### Gaps
- No measurement of battery drain (mW) or SPU power draw at 1 ms vs 8 ms intervals, and no data on M-series efficiency-core scheduling of the callback.
