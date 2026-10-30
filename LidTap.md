# LidTap: zone taps on a MacBook display, no extra hardware

LidTap turns gentle taps on a MacBook's display into input: tap one of a few zones on the screen
and the Mac knows which one. It uses no touch sensor, camera, mirror or add-on. It reads the
motion sensor (IMU) already inside the laptop and learns what a tap in each zone feels like on
your machine.

It is not a touchscreen. It can't track a finger, drag, or detect a press that is held. It answers
one question per tap: **which zone?**

---

## First real results

Measured on an M3 MacBook Air 13" (Mac15,12, macOS 27.0.1), lid at 130–131°, fingertip taps,
2×2 grid, 15 taps per zone (60 taps):

| Layout | Best model | Cross-validated accuracy |
|---|---|---|
| 2×2 (four zones) | SVM | **95%** |
| Top / bottom | SVM | **100%** |
| Left / right | SVM, logistic regression | **95%** |

- Fingertip taps peaked at **3.7–13 °/s** of gyro twist, against an idle noise level of about
  0.1–0.2 °/s. Even a gentle tap stands out clearly.
- All 3 errors were left/right mix-ups within the same row: zone 2 read as zone 1 twice, and
  zone 4 as zone 3 once. Top/bottom was never confused.
- Accuracy against taps per zone: 2 taps 82%, 5 taps 89%, 10 taps 94%.

These numbers come from one session, one lid angle and one surface. Accuracy will drop when the
lid angle or surface changes, until those conditions are part of calibration. 3×3 hasn't been
measured yet.

---

## How it works

### The physics

When you tap the lid, the hinge carries the force into the base and the whole laptop twists a
little. The IMU (a Bosch 6-axis part on the logic board, in the base) measures that twist with its
gyroscope at about 800 Hz.

- **Where** you tap changes the twist. Taps on different sides should twist the laptop in
  opposite directions, and taps nearer or farther from the hinge change the balance of twist to
  shake.
- **Bumping the desk** mostly moves the laptop sideways instead of twisting it. That is why the
  gyroscope, not the accelerometer, is the trigger.

LidTap treats each zone like a fingerprint. It records examples, then matches new taps against
them. It does not try to calculate a position.

### The pipeline

```
IMU (accel + gyro, ~794 Hz each) ──► high-pass 5 Hz ──► |gyro twist| vs adaptive trigger
                                                              │ crosses
                                                              ▼
                                   wait 170 ms ──► cut 200 ms window (30 ms before, 170 ms after)
                                                              │
                     gates: typing / click / scroll in last 0.3 s?  lid moved ≥2°?  ──► ignored
                                                              │ passes
                                                              ▼
                     features (70) ──► classifier ──► open-set check ──► zone + confidence
                                                              │
                                                              ▼
                                           GUI highlight  +  optional shell action
```

1. **Read sensors:** undocumented IOKit HID services (`AppleSPUHIDDevice`, usage page 0xFF00,
   usages 3 and 9). These need the Input Monitoring permission, not root. The lid-angle sensor
   (whole degrees) is polled at 20 Hz for context and to ignore taps while the lid is moving.
2. **Detect taps:** the trigger fires when the high-passed twist magnitude exceeds
   `max(trigger floor, sensitivity × idle noise)`. Idle noise is a running estimate that only
   updates when nothing is happening. A dead time after each tap prevents double triggers.
3. **Gate:** a tap is ignored if a key, click or scroll happened within 0.3 s, using
   `CGEventSourceSecondsSinceLastEventType`, which needs no extra permission. It is also ignored
   if the lid angle changed by 2° or more.
4. **Extract features:** every feature is scaled by tap strength, so soft and firm taps in the
   same zone look alike.
   - Signed direction of the twist at its peak
   - Net early rotation per axis
   - How the twist and the shake split across the three axes
   - Twist per unit of shake, and tap strength
   - How quickly the tap fades, and four frequency bands
   - An 80 ms waveform template, down-weighted so it doesn't dominate the hand-made features
5. **Classify:** five models are cross-validated on every training run: k-nearest neighbours,
   nearest centroid, SVM, logistic regression and random forest. The best one is used
   automatically, or you can pick one.
6. **Reject unknowns:** if a tap is much farther from its predicted zone's examples than taps in
   that zone usually are (default 2×), it is rejected as unfamiliar. Taps that match the recorded
   noise examples are also rejected.

---

## The GUI

Run `./start.sh` and the GUI opens at http://127.0.0.1:8765.

| Tab | What you do there | What it shows |
|---|---|---|
| **1 · Monitor** | Tap gently and tune the detector | Live gyro, twist-magnitude and accelerometer traces; the trigger line; a coloured marker per tap. The last-tap panel shows its waveform, peak twist, peak shake, ratio and lid angle. A log lists every tap. |
| **2 · Calibrate** | Pick a grid, press Start, tap the highlighted zone | Full-screen zone grid with per-zone progress. Zones come up in shuffled groups. "Record 30 s of noise" captures desk knocks and lid moves to reject. Undo, delete and clear. |
| **3 · Model** | Decide which grid your Mac supports | Accuracy for each model on the full grid and on merged layouts (columns, rows, left/right, top/bottom, corners). Confusion matrix, learning curve, 2-D feature map, and the average gyro twist per zone. |
| **4 · Live** | Use it | Full-screen grid lights up with each prediction and its confidence; rejected and ignored taps are shown too. Optionally run a shell command per zone. |

**Status pills (top right):** IMU rate, lid angle, idle noise, current trigger, mode, and the
active model with its accuracy.

### Zone actions

Each zone can run a shell command; `{zone}` becomes the zone number. Actions are off by default.

```
say {zone}
open -a "Mission Control"
open -g "hammerspoon://zone?n={zone}"
open -g "btt://trigger_named/?trigger_name=zone{zone}"
```

---

## Install and run

Needs an Apple Silicon MacBook with the IMU: M2 or later, or M1 Pro/Max. The M1 Air and the 13"
M1 Pro don't have one.

```bash
./start.sh
```

On first run this creates a Python virtualenv with numpy and scikit-learn, using `uv`. It then
starts the server and opens the browser. Stop it with Ctrl+C. If the GUI says no IMU data is
arriving, allow Input Monitoring for the terminal app in System Settings → Privacy & Security →
Input Monitoring, then restart.

Options: `python -m lidtap --port 8765 --data <dir> --open`

### Recommended first session

1. **Monitor:** tap each corner gently. Each tap should cross the dashed line once and leave a
   marker. Typing should show "ignored".
2. **Calibrate:** start with 2×2 at 15 taps per zone, then add 30 s of noise examples.
3. **Model:** if 2×2 is at 90% or more, try 3×3 with 15–20 taps per zone, and keep whichever
   layout stays reliably high.
4. **Live:** turn on actions once predictions look right.

**Tap gently with a fingertip pad.** Pressing hard on a laptop display can leave pressure marks,
and that damage is usually not covered by warranty. A light knuckle tap near the top or side
edges is a safer fallback.

---

## Settings

Saved in `data/config.json` and editable from the GUI.

| Setting | Default | Meaning |
|---|---|---|
| Sensitivity (`k`) | 6 | The trigger is this many times the idle twist noise |
| Trigger floor (`min_thresh`) | 1.0 °/s | The trigger never drops below this |
| Dead time (`refractory`) | 0.35 s | Minimum gap between two taps |
| Ignore after input (`gate_s`) | 0.3 s | Taps this soon after typing, clicking or scrolling are ignored |
| Gating (`gating`) | on | Turns the typing, click, scroll and lid-movement gates on or off |
| Reject factor (`reject_factor`) | 2.0 | How unusual a tap can be before it is rejected |
| Model (`model_kind`) | auto | `auto`, `knn`, `centroid`, `svm`, `logreg` or `rf` |
| Actions | off | Per-zone shell commands |

---

## Data

`data/dataset.json` holds the grid and every labelled tap: zone or `noise`, time, lid angle, peak
values, and the raw 200 ms high-passed gyro and accelerometer windows (160 × 3 each at 800 Hz).
Features are recomputed from the raw windows on load, so improving the feature code improves old
data too. Changing the grid size removes the zone taps but keeps the noise examples.

---

## Code layout

| File | Lines | Role |
|---|---|---|
| `lidtap/sensors.py` | 207 | IOKit access to the IMU and lid-angle sensor, system input timing, mach clock |
| `lidtap/detector.py` | 183 | High-pass filter, adaptive trigger, windowing, gates, scope buffer |
| `lidtap/features.py` | 63 | The 70-dimension tap features |
| `lidtap/model.py` | 214 | Models, cross-validation, merged layouts, learning curve, rejection |
| `lidtap/app.py` | 261 | Calibration flow, dataset, live prediction, actions, status |
| `lidtap/server.py` | 128 | Local HTTP server, live stream to the browser, command API |
| `lidtap/static/` | 809 | GUI: `index.html`, `app.js` (canvas charts, no external libraries), `style.css` |

**Security:** the server listens on 127.0.0.1 only. Because it can run shell commands, every command
needs a random token that is generated each run and embedded in the page, and requests whose Host
header isn't local are refused. Other websites can't change settings or trigger commands.

---

## Limitations

- **Coarse zones only:** no tracking, drag or press-and-hold. Only taps register.
- **Per machine, per setup:** a model trained at one lid angle on a desk may get worse on your lap or
  at a different angle until those conditions are part of calibration.
- **Undocumented sensor:** the IMU interface is private and could change with a macOS update. It
  has worked from macOS 13 through 27.0.1.
- **Lid-angle sensor:** reports whole degrees only and is unreliable on some M1 models.
- **Python prototype:** about 3–5% of one CPU core while streaming, with a delay of roughly 170 ms
  from tap to result, mostly from waiting for the whole tap to finish.

---

## Roadmap

1. **Robustness:** separate calibration profiles keyed on lid angle and desk-versus-lap, a quick
   re-anchor flow, and longer false-trigger tests while typing and using the desk.
2. **Microphone fusion:** add the built-in mic, with Apple's voice processing turned off, as a
   second confirmation and a sound fingerprint. Then measure whether it helps with the left/right
   confusion.
3. **Native app:** a Swift menu-bar app with a background helper, vDSP features and Core ML or
   Swift kNN. The target is under 170 ms latency and about 3% CPU.
4. **Optional research:** webcam hand pose as a hint for where the hand is, and an ultrasonic
   sweep test from the speakers to the mic.

---

## Background

The research behind this approach is in `reports/MacBook lid tap zone detection.md`, with the
supporting notes in `research_notes/`. Key prior work:

- **[yamete](https://github.com/chipcolate/yamete):** showed the gyroscope separates lid slaps from
  desk bumps, and how to read the IMU without root.
- **[olvvier/apple-silicon-accelerometer](https://github.com/olvvier/apple-silicon-accelerometer):**
  IMU report format.
- **TapPrints (MobiSys 2012):** located taps on phone screens from the built-in accelerometer and
  gyroscope with up to about 90% accuracy.
- **Knocker (IMWUT 2019):** identified objects from knocks with about 20 training knocks each.
- **Location template matching (Ing et al.):** match each tap against recorded examples instead of
  computing a position.
