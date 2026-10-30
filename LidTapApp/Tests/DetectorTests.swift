import CoreGraphics
import Foundation

/// Drives TapDetector with synthetic 800 Hz streams that embed real recorded taps.
final class StreamSim {
    let det = TapDetector()
    var events: [TapEvent] = []
    var t: Double
    var lid = 120
    private var rng = SplitMix64(seed: 7)
    let gyroNoise: Double

    init(start: Double = 1000, gyroNoise: Double = 0.1, settings: DetectorSettings = { var s = DetectorSettings(); s.gating = false; return s }()) {
        t = start
        self.gyroNoise = gyroNoise
        det.settings = settings
        det.lidAngle = { [unowned self] in self.lid }
        det.onTap = { [unowned self] in self.events.append($0) }
    }

    private func gauss() -> Double {
        let u = max(Double.random(in: 0..<1, using: &rng), 1e-12), v = Double.random(in: 0..<1, using: &rng)
        return (-2 * log(u)).squareRoot() * cos(2 * .pi * v)
    }

    /// Undoes the detector's 5 Hz high-pass so a recorded (already high-passed) window can be injected as raw
    /// sensor data: y[n] = a(y[n-1] + x[n] - x[n-1])  =>  x[n] = x[n-1] + y[n]/a - y[n-1].
    /// After the window the offset ramps back to zero over 0.4 s (slow enough to stay below any trigger).
    static func unHighPass(_ y: [[Double]]) -> [SIMD3<Double>] {
        let rc = 1 / (2 * Double.pi * 5.0), a = rc / (rc + 1 / TapDetector.fs)
        var x = SIMD3<Double>.zero, prev = SIMD3<Double>.zero
        var out: [SIMD3<Double>] = []
        for r in y {
            let v = SIMD3(r[0], r[1], r[2])
            x = x + v / a - prev
            prev = v
            out.append(x)
        }
        let ramp = Int(0.4 * TapDetector.fs)
        for i in 1...ramp { out.append(x * (1 - Double(i) / Double(ramp))) }
        return out
    }

    /// Feeds `seconds` of noise, adding each tap (a recorded window, trigger at index 24) starting at `at` seconds in.
    func feed(seconds: Double, taps: [(at: Double, sample: TapSample, gain: Double)] = []) {
        let n = Int(seconds * TapDetector.fs)
        let start = t
        let raw = taps.map { (StreamSim.unHighPass($0.sample.g), StreamSim.unHighPass($0.sample.a)) }
        for i in 0..<n {
            let ti = start + Double(i) / TapDetector.fs
            var g = SIMD3(gauss(), gauss(), gauss()) * gyroNoise
            var a = SIMD3(gauss(), gauss(), gauss()) * 0.0003 + SIMD3(0, 0, -1)
            for (j, tap) in taps.enumerated() {
                let k = Int(((ti - start) - tap.at) * TapDetector.fs + 0.5) + TapDetector.trig
                if k >= 0 && k < raw[j].0.count {
                    g += raw[j].0[k] * tap.gain
                    a += raw[j].1[k] * tap.gain
                }
            }
            det.process(.accel, time: ti, value: a)
            det.process(.gyro, time: ti + 0.0001, value: g)
        }
        t = start + Double(n) / TapDetector.fs
    }
}

private func correlation(_ a: [Double], _ b: [Double]) -> Double {
    let ma = a.reduce(0, +) / Double(a.count), mb = b.reduce(0, +) / Double(b.count)
    var num = 0.0, da = 0.0, db = 0.0
    for i in 0..<a.count { num += (a[i] - ma) * (b[i] - mb); da += (a[i] - ma) * (a[i] - ma); db += (b[i] - mb) * (b[i] - mb) }
    return num / max((da * db).squareRoot(), 1e-12)
}

@MainActor
func detectorTests() {
    T.suite = "Detector"
    print("\n▶ Tap detector")
    let ds = T.loadDataset()
    let byLabel = Dictionary(grouping: ds.samples, by: \.label)

    T.run("30 s of idle noise produces no taps") {
        let sim = StreamSim()
        sim.feed(seconds: 30)
        let st = sim.det.currentStatus()
        T.note(String(format: "noise estimate %.3f °/s, trigger %.2f °/s, rate %.0f Hz", st.noise, st.threshold, st.gyroRate))
        T.expect(sim.events.isEmpty, "\(sim.events.count) false taps in idle noise")
        T.expect(abs(st.gyroRate - 800) < 5, "rate \(st.gyroRate)")
    }

    T.run("no trigger during the 1 s warm-up") {
        let sim = StreamSim()
        sim.feed(seconds: 2, taps: [(0.4, ds.samples[0], 1)])
        T.expect(sim.events.isEmpty, "tap during warm-up was reported")
    }

    T.run("each real tap is detected exactly once with a faithful window") {
        let sim = StreamSim()
        sim.feed(seconds: 2)
        var correlations: [Double] = []
        for (i, s) in ds.samples.enumerated() {
            let before = sim.events.count
            sim.feed(seconds: 1, taps: [(0.3, s, 1)])
            let got = sim.events.count - before
            T.expect(got == 1, "sample \(i) (\(s.label), peak \(String(format: "%.1f", s.peakG)) °/s) gave \(got) events")
            if got == 1, let ev = sim.events.last {
                // Features anchor on the tap's onset, so compare the dominant gyro axis from each window's onset.
                let norm = { (g: [[Double]]) in g.map { ($0[0] * $0[0] + $0[1] * $0[1] + $0[2] * $0[2]).squareRoot() } }
                let o1 = Features.onset(norm(ev.g)), o2 = Features.onset(norm(s.g))
                let len = min(TapDetector.n - o1, TapDetector.n - o2, 96)
                let ax = (0..<3).max { a, b in s.g.map { abs($0[a]) }.max()! < s.g.map { abs($0[b]) }.max()! }!
                correlations.append(correlation(ev.g[o1..<(o1 + len)].map { $0[ax] }, s.g[o2..<(o2 + len)].map { $0[ax] }))
            }
        }
        let mean = correlations.reduce(0, +) / Double(max(correlations.count, 1))
        let good = correlations.filter { $0 > 0.8 }.count
        T.note(String(format: "onset-aligned correlation with original: mean %.3f, %d/%d above 0.8, worst %.3f", mean, good, correlations.count, correlations.min() ?? 0))
        T.expect(mean > 0.9 && Double(good) >= 0.9 * Double(correlations.count), "recovered windows differ from the recordings")
    }

    T.run("dead time merges a bounce, separates real double taps") {
        let sim = StreamSim()
        sim.feed(seconds: 2)
        let s = ds.samples[3]
        sim.feed(seconds: 1.5, taps: [(0.2, s, 1), (0.35, s, 1)])  // 150 ms apart: inside 350 ms dead time
        T.expect(sim.events.count == 1, "bounce gave \(sim.events.count) events")
        sim.events.removeAll()
        sim.feed(seconds: 1.5, taps: [(0.2, s, 1), (0.8, s, 1)])  // 600 ms apart
        T.expect(sim.events.count == 2, "double tap gave \(sim.events.count) events")
    }

    T.run("trigger floor rejects taps weaker than it") {
        var settings = DetectorSettings(); settings.gating = false; settings.minThreshold = 20
        let sim = StreamSim(settings: settings)
        sim.feed(seconds: 2, taps: [])
        let weak = ds.samples.min { $0.peakG < $1.peakG }!
        sim.feed(seconds: 1, taps: [(0.3, weak, 1)])
        T.expect(sim.events.isEmpty, "a \(weak.peakG) °/s tap fired above a 20 °/s floor")
        sim.feed(seconds: 1, taps: [(0.3, weak, 30 / weak.peakG)])
        T.expect(sim.events.count == 1, "a 30 °/s tap did not fire")
    }

    T.run("threshold adapts to a noisy surface (k × noise)") {
        let sim = StreamSim(gyroNoise: 0.6)
        sim.feed(seconds: 10)
        let st = sim.det.currentStatus()
        T.note(String(format: "noisy surface: noise %.2f, trigger %.2f °/s, false taps %d", st.noise, st.threshold, sim.events.count))
        T.expect(st.threshold > 3, "threshold did not rise (\(st.threshold))")
        T.expect(sim.events.count <= 1, "\(sim.events.count) false taps on a noisy surface")
    }

    T.run("lid movement gates the tap") {
        var settings = DetectorSettings(); settings.gating = true; settings.gateSeconds = 0
        // Gating also checks real keyboard/mouse timing, so run on the real clock, far from any input.
        let sim = StreamSim(start: MachClock.now() - 3, settings: settings)
        sim.feed(seconds: 2)
        sim.lid = 125
        sim.feed(seconds: 0.2)
        sim.lid = 131
        sim.feed(seconds: 1, taps: [(0.2, ds.samples[0], 1)])
        let reasons = sim.events.map { $0.gated ?? "none" }
        T.note("gate reasons: \(reasons)")
        T.expect(reasons.contains("lid moved") || reasons.contains { ["typing", "click", "scroll"].contains($0) },
                 "tap during lid movement was not gated: \(reasons)")
    }

    T.run("replayed taps through detector + model keep their zone") {
        // Train on even taps, then push the odd ones through the detector in a live-like stream.
        let train = ds.samples.indices.filter { $0 % 2 == 0 }.map { ds.samples[$0] }
        let test = ds.samples.indices.filter { $0 % 2 == 1 }.map { ds.samples[$0] }
        let m = ZoneModel(kind: .logreg, X: train.map { Features.extract(g: $0.g, a: $0.a) }, labels: train.map(\.label),
                          augmented: train.map { Augment.variants(of: $0) })  // trained exactly as the app does
        let sim = StreamSim()
        sim.feed(seconds: 2)
        var correct = 0, rejected = 0
        for s in test {
            let before = sim.events.count
            sim.feed(seconds: 1, taps: [(0.3, s, Double.random(in: 0.7...1.4))])
            guard sim.events.count > before, let ev = sim.events.last else { continue }
            let p = m.predict(Features.extract(g: ev.g, a: ev.a), rejectFactor: 2)
            if p.rejected != nil { rejected += 1 } else if p.label == s.label { correct += 1 }
        }
        T.note("held-out taps through the live path: \(correct)/\(test.count) correct, \(rejected) rejected")
        T.expect(Double(correct) / Double(test.count) >= 0.8, "live-path accuracy \(correct)/\(test.count)")
        _ = byLabel
    }

    T.run("pre-tap motion: still screen vs a wobble just before the tap") {
        let sim = StreamSim()
        sim.feed(seconds: 3)
        sim.feed(seconds: 1, taps: [(0.5, ds.samples[0], 1)])
        let still = sim.events.last?.preMotion ?? -1
        // A 15 Hz wobble at 0.8 °/s (below the trigger) for the 0.4 s before the next tap.
        let start = sim.t
        for i in 0..<Int(0.4 * TapDetector.fs) {
            let t = start + Double(i) / TapDetector.fs
            sim.det.process(.accel, time: t, value: SIMD3(0, 0, -1))
            sim.det.process(.gyro, time: t + 0.0001, value: SIMD3(0.8 * sin(2 * .pi * 15 * (t - start)), 0, 0))
        }
        sim.t = start + 0.4
        sim.feed(seconds: 1, taps: [(0.0, ds.samples[1], 1)])
        let moving = sim.events.last?.preMotion ?? -1
        T.note(String(format: "pre-tap motion: still %.2f °/s, after wobble %.2f °/s", still, moving))
        T.expect(still < 0.6 && moving > 0.6, "pre-motion did not separate a still start from a wobble")
    }

    T.run("scope snapshot is bounded and ordered") {
        let sim = StreamSim()
        sim.feed(seconds: 6)
        let snap = sim.det.scopeSnapshot(seconds: 4)
        T.expect(snap.t.count > 1500 && snap.t.count < 1700, "scope rows \(snap.t.count) for 4 s at 400 Hz")
        T.expect(zip(snap.t, snap.t.dropFirst()).allSatisfy { $0 < $1 }, "scope times not increasing")
        T.expect(snap.t.count == snap.mag.count && snap.t.count == snap.gyro.count, "scope arrays differ in length")
    }

    T.run("throughput: detector handles 800 Hz × 2 streams with headroom") {
        let sim = StreamSim()
        let t0 = Date()
        sim.feed(seconds: 60)
        let dt = Date().timeIntervalSince(t0)
        T.note(String(format: "60 s of sensor data processed in %.2f s (%.0f× real time)", dt, 60 / dt))
        T.expect(dt < 6, "detector too slow: \(dt) s for 60 s of data")
    }
}
