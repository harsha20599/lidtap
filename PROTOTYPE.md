# LidTap prototype (Python)

Zone taps on a MacBook display using only the built-in motion sensor. A tap on the lid twists the
machine about the hinge; the gyroscope in the base feels that twist at ~800 Hz, and a per-machine
classifier learns which zone produced it. Background and sources: `reports/MacBook lid tap zone detection.md`.

## Run

```bash
./start.sh
```

This creates `.venv` on first run, starts the server on http://127.0.0.1:8765 and opens it in your browser.
Needs an Apple Silicon MacBook with the IMU (M2 or later, or M1 Pro/Max). If no data arrives, allow
Input Monitoring for the app that launched it (System Settings → Privacy & Security → Input Monitoring).

## Workflow

1. **Monitor**: watch the live gyro/accel traces. Tap gently and check that taps cross the dashed
   trigger line while typing and desk knocks are ignored. Tune sensitivity and the trigger floor.
2. **Calibrate**: pick a grid (start with 3×3), press Start, and tap the highlighted zone. Use
   *Full screen* so the zones sit exactly where you tap on the display. Add 30 s of noise examples
   (desk knocks, moving the lid). The model retrains when calibration finishes.
3. **Model**: cross-validated accuracy for five classifiers and for merged layouts (columns, rows,
   left/right, corners), plus the confusion matrix, learning curve, feature map and per-zone gyro signatures.
   Choose the finest layout that is reliably high.
4. **Live**: the grid lights up with each prediction; optionally map zones to shell commands
   (`say {zone}`, `open -a "Mission Control"`, Hammerspoon or BetterTouchTool URLs).

Tap gently with a fingertip pad. Pressing hard on the display can cause pressure marks.

## Layout

| File | What it does |
|---|---|
| `lidtap/sensors.py` | IOKit HID access to the IMU and lid-angle sensor; system input timing |
| `lidtap/detector.py` | High-pass filtering, adaptive gyro trigger, tap windowing, input/lid gating |
| `lidtap/features.py` | Strength-normalised twist direction, energy split, ratios, spectrum, waveform template |
| `lidtap/model.py` | Classifiers, cross-validation, merged layouts, learning curve, open-set rejection |
| `lidtap/app.py` | Calibration flow, dataset, live prediction, actions |
| `lidtap/server.py` | Local HTTP + Server-Sent Events; POSTs need the per-run page token |
| `lidtap/static/` | The GUI |
| `data/` | `dataset.json` (every labelled tap with raw windows) and `config.json` |
