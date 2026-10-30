"""Tap detection on the gyroscope stream.

A lid tap twists the whole machine about the hinge, so the high-passed gyroscope magnitude is the
trigger signal (yamete found the gyro, not the accelerometer, separates lid hits from desk bumps).
When it crosses an adaptive threshold we wait for the rest of the tap, cut a fixed window of
gyro + accel around the trigger, resample it onto an 800 Hz grid and hand it on as an event.
"""

import itertools
import math
import queue
import threading
import time
from collections import deque

import numpy as np

from . import sensors

FS = 800.0
PRE_S, POST_S = 0.03, 0.17
N = int(round((PRE_S + POST_S) * FS))  # samples per tap window
TRIG = int(round(PRE_S * FS))  # index of the trigger inside the window
PLOT_DECIMATE = 2  # rows sent to the GUI scope (400 Hz is plenty to draw)


class HighPass3:
    """First-order high-pass on a 3-axis stream; removes gravity and slow drift."""

    def __init__(self, fc=5.0, fs=FS):
        rc = 1.0 / (2 * math.pi * fc)
        self.a = rc / (rc + 1.0 / fs)
        self.px = None
        self.py = (0.0, 0.0, 0.0)

    def __call__(self, x, y, z):
        if self.px is None:
            self.px = (x, y, z)
        a, (px, py, pz), (qx, qy, qz) = self.a, self.px, self.py
        out = (a * (qx + x - px), a * (qy + y - py), a * (qz + z - pz))
        self.px, self.py = (x, y, z), out
        return out


class Detector(threading.Thread):
    def __init__(self, sens, cfg, on_event):
        super().__init__(name="detector", daemon=True)
        self.sens = sens
        self.cfg = cfg  # live dict shared with the app: k, min_thresh, refractory, gate_s, gating
        self.on_event = on_event
        self.hp = {"gyro": HighPass3(), "accel": HighPass3()}
        self.buf = {"gyro": deque(maxlen=4000), "accel": deque(maxlen=4000)}  # (t, x, y, z) high-passed
        self.last_accel = (0.0, 0.0, 0.0)
        self.noise_ms = None  # EMA of |gyro|^2 while quiet
        self.threshold = cfg["min_thresh"]
        self.warm_until = None
        self.refractory_until = 0.0
        self.quiet_until = 0.0
        self.pending = []  # trigger times waiting for the end of their window
        self.lid_hist = deque(maxlen=200)  # (t, angle)
        self.latest_t = 0.0
        self.rows = deque(maxlen=4000)  # (seq, t, gx, gy, gz, ax, ay, az, mag) for the scope
        self.seq = 0
        self._decim = 0
        self.rows_lock = threading.Lock()
        self.rates = {"gyro": 0.0, "accel": 0.0}
        self._counts = {"gyro": 0, "accel": 0}
        self._rate_t = time.monotonic()
        self.event_id = 0

    # -- stream processing -------------------------------------------------------------------

    def run(self):
        q = self.sens.samples
        last_lid = 0.0
        while True:
            try:
                item = q.get(timeout=0.02)
            except queue.Empty:
                item = None
            while item is not None:
                self._sample(*item)
                try:
                    item = q.get_nowait()
                except queue.Empty:
                    item = None
            t = sensors.now()
            if t - last_lid > 0.05 and self.sens.lid_angle is not None:
                self.lid_hist.append((t, self.sens.lid_angle))
                last_lid = t
            while self.pending and self.latest_t >= self.pending[0] + POST_S:
                self._finish(self.pending.pop(0))
            self._update_rates()

    def _update_rates(self):
        el = time.monotonic() - self._rate_t
        if el >= 1.0:
            self.rates = {k: c / el for k, c in self._counts.items()}
            self._counts = {k: 0 for k in self._counts}
            self._rate_t = time.monotonic()

    def _sample(self, kind, t, x, y, z):
        self._counts[kind] += 1
        hx, hy, hz = self.hp[kind](x, y, z)
        self.buf[kind].append((t, hx, hy, hz))
        if kind == "accel":
            self.last_accel = (hx, hy, hz)
            return
        self.latest_t = t
        mag = math.sqrt(hx * hx + hy * hy + hz * hz)
        self._detect(t, mag)
        self._decim += 1
        if self._decim >= PLOT_DECIMATE:
            self._decim = 0
            with self.rows_lock:
                self.seq += 1
                self.rows.append((self.seq, t, hx, hy, hz, *self.last_accel, mag))

    def _detect(self, t, mag):
        cfg = self.cfg
        if self.warm_until is None:
            self.warm_until = t + 1.0
        if self.noise_ms is None:
            self.noise_ms = mag * mag
        noise = math.sqrt(self.noise_ms)
        self.threshold = max(cfg["min_thresh"], cfg["k"] * noise)
        if mag > self.threshold:
            if t >= self.warm_until and t >= self.refractory_until:
                self.pending.append(t)
                self.refractory_until = t + cfg["refractory"]
            self.quiet_until = t + 0.5
        elif t >= self.quiet_until:
            self.noise_ms += (mag * mag - self.noise_ms) / (2.0 * FS)  # ~2 s time constant

    # -- event extraction --------------------------------------------------------------------

    def _window(self, kind, t0):
        recent = list(itertools.islice(reversed(self.buf[kind]), int((POST_S + PRE_S + 0.3) * FS)))
        if len(recent) < 8:
            return np.zeros((N, 3))
        arr = np.array(recent[::-1])
        grid = t0 - PRE_S + np.arange(N) / FS
        return np.column_stack([np.interp(grid, arr[:, 0], arr[:, k]) for k in (1, 2, 3)])

    def _gate(self, t0):
        cfg = self.cfg
        if not cfg.get("gating", True):
            return None
        t_now = sensors.now()
        for kind, secs in sensors.seconds_since_input().items():
            if t_now - secs >= t0 - cfg["gate_s"]:
                return kind
        angles = [a for (t, a) in self.lid_hist if t >= t0 - 0.5]
        if angles and max(angles) - min(angles) >= 2:
            return "lid moved"
        return None

    def _finish(self, t0):
        g = self._window("gyro", t0)
        a = self._window("accel", t0)
        gm = np.linalg.norm(g, axis=1)
        am = np.linalg.norm(a, axis=1)
        self.event_id += 1
        self.on_event({
            "id": self.event_id,
            "t": t0,
            "wall": time.time(),
            "g": g,
            "a": a,
            "peak_g": float(gm.max()),
            "peak_a": float(am.max()),
            "lid": self.sens.lid_angle,
            "threshold": self.threshold,
            "noise": math.sqrt(self.noise_ms or 0.0),
            "gated": self._gate(t0),
        })

    def rows_since(self, seq):
        with self.rows_lock:
            if not self.rows or self.rows[-1][0] <= seq:
                return []
            start = max(0, len(self.rows) - (self.rows[-1][0] - seq))
            return list(itertools.islice(self.rows, start, None))
