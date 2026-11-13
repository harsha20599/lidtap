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
    /// Scales only the twist of injected taps, to play a tap as a heavier Mac feels it: far less twist, some jolt.
    var twistScale = 1.0

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
    /// After the window the offset eases back to zero over 0.4 s (a raised cosine: slow and without a corner, so it
    /// stays below both the twist and the jolt trigger).
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
        for i in 1...ramp { out.append(x * (0.5 + 0.5 * cos(Double.pi * Double(i) / Double(ramp)))) }
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
                    g += raw[j].0[k] * tap.gain * twistScale
                    a += raw[j].1[k] * tap.gain
                }
            }
            det.process(.accel, time: ti, value: a)
            det.process(.gyro, time: ti + 0.0001, value: g)
        }
        t = start + Double(n) / TapDetector.fs
    }

    /// Feeds a real recording, sample for sample at its own rate. Event times are then seconds into the recording.
    func feed(_ stream: RawStream) {
        t = 0
        for i in stream.gyro.indices {
            let ti = Double(i) / stream.rate
            det.process(.accel, time: ti, value: stream.accel[i])
            det.process(.gyro, time: ti + 0.0001, value: stream.gyro[i])
        }
        t = Double(stream.gyro.count) / stream.rate
    }

    /// Feeds raw gyro and accelerometer values produced by `motion` (seconds since the call -> deg/s, g) on top of the noise.
    func feed(seconds: Double, motion: (Double) -> (SIMD3<Double>, SIMD3<Double>)) {
        let n = Int(seconds * TapDetector.fs), start = t
        for i in 0..<n {
            let ti = start + Double(i) / TapDetector.fs
            let (mg, ma) = motion(ti - start)
            det.process(.accel, time: ti, value: SIMD3(gauss(), gauss(), gauss()) * 0.0003 + SIMD3(0, 0, -1) + ma)
            det.process(.gyro, time: ti + 0.0001, value: SIMD3(gauss(), gauss(), gauss()) * gyroNoise + mg)
        }
        t = start + Double(n) / TapDetector.fs
    }
}

/// The taps a detector finds in a real recording, labelled by the corner being tapped at the time.
func labelledTaps(in stream: RawStream, settings: DetectorSettings = DetectorSettings()) -> (taps: [(label: String, event: TapEvent)], all: [TapEvent]) {
    let sim = StreamSim(settings: settings)
    sim.feed(stream)
    var taps: [(String, TapEvent)] = []
    for seg in stream.segments where zoneIndex(seg.name) != nil {
        for e in sim.events where e.time >= seg.start && e.time < seg.end && e.gated == nil { taps.append((seg.name, e)) }
    }
    return (taps, sim.events)
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

    T.run("a heavy Mac's light tap (hardly any twist, a clear jolt) is felt by its jolt") {
        // Real taps replayed as a 14" MacBook Pro feels them: about 0.6 °/s of twist and 5 to 15 milli-g of jolt.
        func felt(jolt: Bool) -> Int {
            let sim = StreamSim()
            sim.twistScale = 0.25
            sim.det.impactTriggerEnabled = jolt
            sim.feed(seconds: 2)
            for s in ds.samples { sim.feed(seconds: 1, taps: [(0.3, s, 0.35)]) }
            return sim.events.count
        }
        let both = felt(jolt: true), twistOnly = felt(jolt: false)
        T.note("felt \(both) of \(ds.samples.count) with twist or jolt, \(twistOnly) with the twist alone")
        T.expect(both >= ds.samples.count - 2 && both <= ds.samples.count, "felt \(both) of \(ds.samples.count)")
        T.expect(twistOnly * 3 < both, "the twist alone felt \(twistOnly)")
    }

    // A real recording from a 14" MacBook Pro on a desk: 5 s still, light taps on each screen corner, typing, still.
    // Its screen taps twist the base 0.3 to 1.5 °/s (a 13" Air: 5 to 10), mostly under a 1 °/s twist trigger.
    T.run("14-inch MacBook Pro: light taps on every corner are felt, a still desk gives none") {
        let pro = try T.loadStream()
        let (taps, all) = labelledTaps(in: pro)
        let perZone = (0..<4).map { z in taps.filter { $0.label == zoneLabel(z) }.count }
        let still = ["still", "still2"].map { pro.segment($0) }
        let stillEvents = all.filter { e in still.contains { e.time >= $0.start && e.time < $0.end } }.count
        let twist = taps.map(\.event.peakG).sorted(), jolt = taps.map { $0.event.impact * 1000 }.sorted()
        T.note("taps felt per corner \(perZone), in the still stretches \(stillEvents)")
        T.note(String(format: "their twist: median %.2f °/s (%d of %d under 1 °/s) · their jolt: median %.1f mg", twist[twist.count / 2],
                      twist.filter { $0 < 1 }.count, twist.count, jolt[jolt.count / 2]))
        T.expect(perZone.allSatisfy { $0 >= 5 }, "taps felt per corner \(perZone), want at least 5 each")
        T.expect(stillEvents == 0, "\(stillEvents) taps on a still desk")
    }

    T.run("14-inch MacBook Pro: the twist alone would miss most of its taps") {
        // The trigger as it was: twist only.
        let pro = try T.loadStream()
        let sim = StreamSim()
        sim.det.impactTriggerEnabled = false
        sim.feed(pro)
        let zones = pro.segments.filter { zoneIndex($0.name) != nil }
        let found = sim.events.filter { e in zones.contains { e.time >= $0.start && e.time < $0.end } }.count
        let (taps, _) = labelledTaps(in: pro)
        T.note("twist only: \(found) taps · twist or jolt: \(taps.count)")
        T.expect(found * 3 < taps.count, "twist-only trigger found \(found) of \(taps.count)")
    }

    T.run("resting level ignores a burst: a tap right after typing or a nudge is still felt") {
        let sim = StreamSim()
        sim.feed(seconds: 4)
        let rest = sim.det.currentStatus()
        // Two seconds of the Mac being moved about (3 Hz, 6 °/s), as when typing hard or shifting it on the desk.
        sim.feed(seconds: 2) { t in (SIMD3(6 * sin(2 * .pi * 3 * t), 2 * sin(2 * .pi * 4.3 * t), 0), .zero) }
        sim.feed(seconds: 0.6)
        let after = sim.det.currentStatus()
        T.note(String(format: "trigger at rest %.2f °/s, 0.6 s after the burst %.2f °/s", rest.threshold, after.threshold))
        T.expect(after.threshold < 1.5 * rest.threshold, "trigger still raised after the burst: \(after.threshold) vs \(rest.threshold)")
        sim.events.removeAll()
        sim.feed(seconds: 1, taps: [(0.2, ds.samples[0], 0.4)])  // a light tap, 0.4x
        T.expect(sim.events.count == 1, "a light tap 0.8 s after the burst gave \(sim.events.count) events")
    }

    T.run("resting level follows a surface that keeps moving") {
        let sim = StreamSim(settings: DetectorSettings())  // gating on, as in the app
        sim.feed(seconds: 3)
        // A lap: slow sway that never stops.
        sim.feed(seconds: 6) { t in (SIMD3(1.5 * sin(2 * .pi * 2.2 * t), 1.0 * sin(2 * .pi * 3.1 * t), 0), .zero) }
        let st = sim.det.currentStatus()
        T.note(String(format: "on a swaying surface: resting %.2f °/s, trigger %.2f °/s, events %d", st.noise, st.threshold, sim.events.count))
        T.expect(st.noise > 0.5, "resting level did not rise on a moving surface: \(st.noise)")
        T.expect(sim.events.filter { $0.gated == nil }.isEmpty, "sway alone gave \(sim.events.count) taps")
        sim.events.removeAll()
        sim.feed(seconds: 1, taps: [(0.3, ds.samples[0], 1)])
        T.expect(sim.events.count == 1 && sim.events[0].gated == nil, "a tap on the swaying surface: \(sim.events.map { $0.gated ?? "tap" })")
    }

    T.run("a twist with no jolt is not a tap (the Mac being pushed or rocked)") {
        let sim = StreamSim(settings: DetectorSettings())  // gating on
        sim.feed(seconds: 3)
        // A smooth 4 °/s push lasting 0.25 s: plenty of twist, nothing a fingertip landing would leave.
        sim.feed(seconds: 1) { t in t < 0.25 ? (SIMD3(4 * sin(.pi * t / 0.25), 0, 0), .zero) : (.zero, .zero) }
        T.note("push: \(sim.events.map { $0.gated ?? "tap" }) \(sim.events.first?.gateDetail ?? "")")
        T.expect(!sim.events.isEmpty && sim.events.allSatisfy { $0.gated == TapDetector.notATap }, "a push was taken for a tap: \(sim.events.map { $0.gated ?? "tap" })")
        sim.events.removeAll()
        sim.feed(seconds: 1, taps: [(0.3, ds.samples[0], 1)])
        T.expect(sim.events.count == 1 && sim.events[0].gated == nil, "a real tap after it: \(sim.events.map { $0.gated ?? "tap" })")
    }

    T.run("tap strength: the twist or the jolt, whichever this Mac shows more of") {
        let air = ds.samples.filter { $0.label != noiseLabel }.map { TapStrength.strength(twist: $0.peakG, impact: TapStrength.impact($0.a)) }.sorted()
        T.note(String(format: "13-inch Air taps: median strength %.1f", air[air.count / 2]))
        T.expect(air.first! >= TapStrength.ceiling, "an Air tap of strength \(air.first!) would be refused")
        if let pro = try? T.loadStream() {
            let (taps, _) = labelledTaps(in: pro)
            let heavy = taps.map(\.event.strength).sorted()
            T.note(String(format: "14-inch Pro taps: median strength %.1f (twist alone %.1f)", heavy[heavy.count / 2], taps.map(\.event.peakG).sorted()[taps.count / 2]))
            T.expect(heavy[heavy.count / 2] > 2, "the Pro's typical tap is only strength \(heavy[heavy.count / 2])")
        }
        // A 14" Pro's light tap: 0.7 deg/s of twist, 8 milli-g of jolt. The jolt decides.
        T.expect(abs(TapStrength.strength(twist: 0.7, impact: 0.0084) - 2.8) < 1e-9, "a heavy Mac's tap should be measured by its jolt")
        T.expect(TapStrength.impact(Array(repeating: [0, 0, -1], count: 160)) < 1e-9, "gravity alone read as a jolt")
        // The limit follows the weakest corner, so a strong corner can't shut a weak one out.
        let byZone = ["z0": [1.2, 1.5, 1.8, 1.4], "z2": [8.0, 9, 7.5, 10]]
        T.expect(abs(TapStrength.learned(byZone: byZone) - 1.0) < 1e-9, "limit \(TapStrength.learned(byZone: byZone)) with one weak corner")
        T.expect(TapStrength.learned(from: byZone.values.flatMap { $0 }) > 2, "the pooled limit should have been the unfair one")
        T.expect(TapStrength.learned(byZone: ["z0": [3.0, 3.3, 2.7], "z1": [9, 9, 9]]) == 1.5, "half of the weakest corner's typical tap")
        T.expect(TapStrength.learned(byZone: ["z0": [2.0], "z1": [2.2, 1.8]]) == TapStrength.learned(from: [2.0, 2.2, 1.8]), "too few taps per corner: all taps together")
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
