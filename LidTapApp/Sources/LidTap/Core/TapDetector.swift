import CoreGraphics
import Foundation

struct DetectorSettings: Codable, Equatable {
    var k: Double = 6            // trigger at k x idle gyro noise ...
    var minThreshold: Double = 1 // ... but never below this many deg/s
    var refractory: Double = 0.5   // people wait for the wobble to settle before the next tap
    var gateSeconds: Double = 0.3
    var gating: Bool = true

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DetectorSettings()
        k = try c.decodeIfPresent(Double.self, forKey: .k) ?? d.k
        minThreshold = try c.decodeIfPresent(Double.self, forKey: .minThreshold) ?? d.minThreshold
        refractory = try c.decodeIfPresent(Double.self, forKey: .refractory) ?? d.refractory
        gateSeconds = try c.decodeIfPresent(Double.self, forKey: .gateSeconds) ?? d.gateSeconds
        gating = try c.decodeIfPresent(Bool.self, forKey: .gating) ?? d.gating
    }
}

/// A tap window cut around the trigger: 160 samples (200 ms at 800 Hz) of high-passed gyro and accel.
struct TapEvent {
    let id: Int
    let time: Double
    let date: Date
    let g: [[Double]]
    let a: [[Double]]
    let peakG: Double
    let peakA: Double
    let lid: Int?
    let threshold: Double
    let noise: Double
    let gated: String?
    /// Why it was gated, for diagnostics (e.g. "flagsChanged 120 ms before the tap").
    var gateDetail: String? = nil
    /// Strongest twist (deg/s) in the 300 ms before the tap. A deliberate tap starts from a still screen;
    /// typing and a lid still wobbling from the last tap do not.
    var preMotion: Double = 0
}

struct DetectorStatus {
    var gyroRate: Double = 0
    var accelRate: Double = 0
    var noise: Double = 0
    var threshold: Double = 0
}

struct ScopeSnapshot {
    var t: [Double] = []
    var gyro: [SIMD3<Double>] = []
    var mag: [Double] = []
    var threshold: Double = 1
    var taps: [Double] = []
}

private struct HighPass3 {
    let a: Double
    var previousIn: SIMD3<Double>?
    var previousOut = SIMD3<Double>.zero

    init(fc: Double = 5, fs: Double = TapDetector.fs) {
        let rc = 1 / (2 * Double.pi * fc)
        a = rc / (rc + 1 / fs)
    }

    mutating func callAsFunction(_ v: SIMD3<Double>) -> SIMD3<Double> {
        let p = previousIn ?? v
        let out = a * (previousOut + v - p)
        previousIn = v
        previousOut = out
        return out
    }
}

/// Fixed-capacity history of timestamped 3-axis samples.
private struct Ring3 {
    let capacity: Int
    var t: [Double], v: [SIMD3<Double>]
    var head = 0, count = 0

    init(capacity: Int) {
        self.capacity = capacity
        t = Array(repeating: 0, count: capacity)
        v = Array(repeating: .zero, count: capacity)
    }

    mutating func append(_ time: Double, _ value: SIMD3<Double>) {
        t[head] = time
        v[head] = value
        head = (head + 1) % capacity
        count = min(count + 1, capacity)
    }

    func slot(newest i: Int) -> Int { (head - 1 - i + 2 * capacity) % capacity }

    /// Largest |value| between two times (newest-first scan, stops once past `from`).
    func maxMagnitude(from: Double, to: Double) -> Double {
        var best = 0.0
        var i = 0
        while i < count {
            let k = slot(newest: i)
            if t[k] < from { break }
            if t[k] <= to { best = max(best, (v[k] * v[k]).sum().squareRoot()) }
            i += 1
        }
        return best
    }

    /// Resample onto `n` points at `fs`, starting at `start` (linear interpolation, clamped at the edges).
    func resample(start: Double, n: Int, fs: Double) -> [[Double]] {
        var idx: [Int] = []
        var i = 0
        while i < count {
            let k = slot(newest: i)
            idx.append(k)
            if t[k] < start - 0.01 { break }
            i += 1
        }
        idx.reverse()
        guard idx.count >= 2 else { return Array(repeating: [0, 0, 0], count: n) }
        var out = [[Double]](repeating: [0, 0, 0], count: n)
        var j = 0
        for s in 0..<n {
            let tg = start + Double(s) / fs
            while j < idx.count - 2 && t[idx[j + 1]] < tg { j += 1 }
            let k0 = idx[j], k1 = idx[j + 1]
            let span = t[k1] - t[k0]
            let w = span > 0 ? min(max((tg - t[k0]) / span, 0), 1) : 0
            let p = v[k0] + (v[k1] - v[k0]) * w
            out[s] = [p.x, p.y, p.z]
        }
        return out
    }
}

/// Finds taps in the gyroscope stream.
///
/// A lid tap twists the machine about the hinge, so the high-passed gyro magnitude is the trigger:
/// it fires above max(floor, k x idle noise), then waits for the rest of the tap and cuts a window.
final class TapDetector {
    static let fs = 800.0
    static let pre = 0.03, post = 0.17
    static let n = 160, trig = 24

    var onTap: ((TapEvent) -> Void)?
    var lidAngle: () -> Int? = { nil }

    private let lock = NSLock()
    private var _settings = DetectorSettings()
    var settings: DetectorSettings {
        get { lock.withLock { _settings } }
        set { lock.withLock { _settings = newValue } }
    }

    private var hpGyro = HighPass3(), hpAccel = HighPass3()
    private var gyro = Ring3(capacity: 4096), accel = Ring3(capacity: 4096)
    private var noiseMS: Double?
    private var warmSum = 0.0, warmCount = 0
    private var threshold = 1.0
    private var warmUntil: Double?
    private var refractoryUntil = 0.0, quietUntil = 0.0, lastAbove = -Double.infinity
    private var pending: [Double] = []
    private var lidHistory: [(Double, Int)] = []
    private var gyroCount = 0, accelCount = 0, rateStart: Double?
    private var status = DetectorStatus()
    private var eventID = 0
    private var scope = Ring3(capacity: 3600)  // decimated gyro for drawing
    private var scopeMag: [Double] = Array(repeating: 0, count: 3600)
    private var decimate = 0
    private var recentTaps: [Double] = []

    func process(_ kind: IMUReader.Kind, time: Double, value: SIMD3<Double>) {
        var finished: [TapEvent] = []
        lock.lock()
        switch kind {
        case .accel:
            accelCount += 1
            accel.append(time, hpAccel(value))
        case .gyro:
            gyroCount += 1
            let h = hpGyro(value)
            gyro.append(time, h)
            let mag = (h * h).sum().squareRoot()
            detect(time: time, mag: mag)
            decimate += 1
            if decimate >= 2 {
                decimate = 0
                scopeMag[scope.head] = mag
                scope.append(time, h)
            }
            if gyroCount % 40 == 0, let angle = lidAngle() {
                lidHistory.append((time, angle))
                if lidHistory.count > 100 { lidHistory.removeFirst(lidHistory.count - 100) }
            }
            while let first = pending.first, time >= first + Self.post {
                pending.removeFirst()
                finished.append(finish(t0: first))
            }
        }
        if let start = rateStart {
            if time - start >= 1 {
                status.gyroRate = Double(gyroCount) / (time - start)
                status.accelRate = Double(accelCount) / (time - start)
                gyroCount = 0
                accelCount = 0
                rateStart = time
            }
        } else {
            rateStart = time
        }
        lock.unlock()
        for event in finished { onTap?(event) }
    }

    private func detect(time t: Double, mag: Double) {
        if warmUntil == nil { warmUntil = t + 1 }
        // Noise floor: averaged over the 1 s warm-up, then a slow (~2 s) average outside taps. Each update is
        // clipped at 4x the current level so a tap can't inflate it, yet it still rises on a genuinely noisy
        // surface (an estimate that only updated below the trigger could get stuck under it forever).
        if t < warmUntil! {
            warmSum += mag * mag
            warmCount += 1
            noiseMS = warmSum / Double(warmCount)
        } else if t >= quietUntil, let ms = noiseMS {
            let clip = 16 * max(ms, 1e-6)
            noiseMS = ms + (min(mag * mag, clip) - ms) / (2 * Self.fs)
        }
        let noise = (noiseMS ?? 0).squareRoot()
        threshold = max(_settings.minThreshold, _settings.k * noise)
        status.noise = noise
        status.threshold = threshold
        guard mag > threshold else { return }
        // Re-arm only after the dead time AND 80 ms below the trigger, so one ringing tap can't fire twice.
        if t >= warmUntil!, t >= refractoryUntil, t - lastAbove > 0.08 {
            pending.append(t)
            refractoryUntil = t + _settings.refractory
            quietUntil = t + 0.5
        }
        lastAbove = t
    }

    private func finish(t0: Double) -> TapEvent {
        let start = t0 - Self.pre
        let g = gyro.resample(start: start, n: Self.n, fs: Self.fs)
        let a = accel.resample(start: start, n: Self.n, fs: Self.fs)
        let norm: ([Double]) -> Double = { ($0[0] * $0[0] + $0[1] * $0[1] + $0[2] * $0[2]).squareRoot() }
        eventID += 1
        recentTaps.append(t0)
        if recentTaps.count > 30 { recentTaps.removeFirst() }
        let gated = gate(t0: t0)
        return TapEvent(id: eventID, time: t0, date: Date(), g: g, a: a,
                        peakG: g.map(norm).max() ?? 0, peakA: a.map(norm).max() ?? 0,
                        lid: lidAngle(), threshold: threshold, noise: status.noise, gated: gated?.reason, gateDetail: gated?.detail,
                        preMotion: gyro.maxMagnitude(from: t0 - 0.33, to: t0 - 0.03))
    }

    /// Lid movement only: keyboard, click and scroll filtering happens in AppModel, which has the full input
    /// history and knows whether LidTap is calibrating.
    private func gate(t0: Double) -> (reason: String, detail: String)? {
        guard _settings.gating else { return nil }
        let angles = lidHistory.filter { $0.0 >= t0 - 0.5 }.map(\.1)
        if let lo = angles.min(), let hi = angles.max(), hi - lo >= 2 { return ("lid moved", "lid angle \(lo)° to \(hi)°") }
        return nil
    }

    func currentStatus() -> DetectorStatus { lock.withLock { status } }

    func scopeSnapshot(seconds: Double) -> ScopeSnapshot {
        lock.withLock {
            var snap = ScopeSnapshot()
            snap.threshold = threshold
            guard scope.count > 0 else { return snap }
            let newest = scope.t[scope.slot(newest: 0)]
            var i = 0
            var idx: [Int] = []
            while i < scope.count {
                let k = scope.slot(newest: i)
                if scope.t[k] < newest - seconds { break }
                idx.append(k)
                i += 1
            }
            idx.reverse()
            snap.t = idx.map { scope.t[$0] }
            snap.gyro = idx.map { scope.v[$0] }
            snap.mag = idx.map { scopeMag[$0] }
            snap.taps = recentTaps.filter { $0 >= newest - seconds }
            return snap
        }
    }
}
