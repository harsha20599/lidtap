import Foundation

/// Not pass/fail: measures where accuracy is lost between recorded taps and the live detector path.
@MainActor
func diagnosticTests() {
    T.suite = "Diagnostics"
    print("\n▶ Diagnostics: live-path accuracy breakdown")
    let ds = T.loadDataset()
    let train = ds.samples.indices.filter { $0 % 2 == 0 }.map { ds.samples[$0] }
    let test = ds.samples.indices.filter { $0 % 2 == 1 }.map { ds.samples[$0] }
    let m = ZoneModel(kind: .logreg, X: train.map { Features.extract(g: $0.g, a: $0.a) }, labels: train.map(\.label))
    func score(_ windows: [(g: [[Double]], a: [[Double]], label: String)]) -> String {
        var ok = 0, rej = 0
        for w in windows {
            let p = m.predict(Features.extract(g: w.g, a: w.a), rejectFactor: 2)
            if p.rejected != nil { rej += 1 } else if p.label == w.label { ok += 1 }
        }
        return "\(ok)/\(windows.count) correct, \(rej) rejected"
    }
    T.run("direct held-out windows") { T.note(score(test.map { ($0.g, $0.a, $0.label) })) }
    T.run("held-out windows scaled 0.7× / 1.4×") {
        for k in [0.7, 1.4] { T.note("\(k)×: " + score(test.map { s in (s.g.map { $0.map { $0 * k } }, s.a.map { $0.map { $0 * k } }, s.label) })) }
    }
    T.run("trigger timing vs injected tap") {
        let sim = StreamSim(gyroNoise: 0.1)
        sim.feed(seconds: 2)
        var rows: [String] = []
        for s in test.prefix(30) {
            let start = sim.t, before = sim.events.count
            sim.feed(seconds: 1, taps: [(0.3, s, 1)])
            let evs = sim.events[before...].map { Int((($0.time - (start + 0.3)) * 800).rounded()) }
            let gm = s.g.map { ($0[0]*$0[0] + $0[1]*$0[1] + $0[2]*$0[2]).squareRoot() }
            let firstAbove = gm.firstIndex { $0 > 1.02 } ?? -1
            rows.append("\(s.label) trig@\(evs) recFirst>thr@\(firstAbove - 24) onset@\(Features.onset(gm) - 24)")
        }
        for r in rows { T.note(r) }
    }
    for gain in [1.0, 0.7, 1.4] {
        T.run("through detector, gain \(gain)") {
            let sim = StreamSim(gyroNoise: 0.1)
            sim.feed(seconds: 2)
            var wins: [(g: [[Double]], a: [[Double]], label: String)] = []
            var offsets: [Int] = []
            for s in test {
                let before = sim.events.count
                sim.feed(seconds: 1, taps: [(0.3, s, gain)])
                guard sim.events.count > before, let ev = sim.events.last else { continue }
                wins.append((ev.g, ev.a, s.label))
                let pk = { (g: [[Double]]) in g.indices.max { a, b in g[a].map { $0 * $0 }.reduce(0, +) < g[b].map { $0 * $0 }.reduce(0, +) }! }
                offsets.append(pk(ev.g) - pk(s.g))
            }
            T.note(score(wins) + ", peak index shift vs recording: \(offsets.sorted())")
        }
    }
}

/// Sweeps the open-set reject factor: real taps at several strengths through the live path vs random junk.
@MainActor
func rejectSweep() {
    T.suite = "Diagnostics"
    print("\n▶ Reject-factor sweep")
    let ds = T.loadDataset()
    let train = ds.samples.indices.filter { $0 % 2 == 0 }.map { ds.samples[$0] }
    let test = ds.samples.indices.filter { $0 % 2 == 1 }.map { ds.samples[$0] }
    for kind in [ModelKind.logreg, .knn] {
        let m = ZoneModel(kind: kind, X: train.map { Features.extract(g: $0.g, a: $0.a) }, labels: train.map(\.label))
        var live: [(f: [Double], label: String)] = []
        for gain in [0.6, 0.8, 1.0, 1.25, 1.6] {
            let sim = StreamSim(gyroNoise: 0.15)
            sim.feed(seconds: 2)
            for s in test {
                let before = sim.events.count
                sim.feed(seconds: 1, taps: [(0.3, s, gain)])
                if sim.events.count > before, let ev = sim.events.last { live.append((Features.extract(g: ev.g, a: ev.a), s.label)) }
            }
        }
        var junk: [[Double]] = []
        for seed in 0..<200 {
            var rng = SplitMix64(seed: UInt64(seed + 5000))
            let amp = Double.random(in: 1...8, using: &rng)
            let g = (0..<TapDetector.n).map { i in (0..<3).map { _ in Double.random(in: -1...1, using: &rng) * amp * exp(-Double(max(i - 24, 0)) / Double.random(in: 10...60, using: &rng)) } }
            junk.append(Features.extract(g: g, a: g.map { $0.map { $0 / Double.random(in: 100...600, using: &rng) } }))
        }
        T.run("\(kind.title): live taps (5 strengths × 30) vs 200 junk windows") {
            for factor in [2.0, 2.5, 3.0, 3.5, 4.0, 5.0] {
                var correct = 0, wrong = 0, rejected = 0
                for x in live {
                    let p = m.predict(x.f, rejectFactor: factor)
                    if p.rejected != nil { rejected += 1 } else if p.label == x.label { correct += 1 } else { wrong += 1 }
                }
                let junkAccepted = junk.filter { m.predict($0, rejectFactor: factor).rejected == nil }.count
                T.note(String(format: "factor %.1f: correct %d, wrong %d, rejected %d of %d · junk accepted %d/200", factor, correct, wrong, rejected, live.count, junkAccepted))
            }
        }
    }
}

/// Does training on augmented copies (sensor noise + timing jitter) make the live path more robust?
@MainActor
func augmentDiag() {
    T.suite = "Diagnostics"
    print("\n▶ Augmentation experiment")
    let ds = T.loadDataset()
    let train = ds.samples.indices.filter { $0 % 2 == 0 }.map { ds.samples[$0] }
    let test = ds.samples.indices.filter { $0 % 2 == 1 }.map { ds.samples[$0] }
    var live: [(f: [Double], label: String)] = []
    for gain in [0.6, 0.8, 1.0, 1.25, 1.6] {
        let sim = StreamSim(gyroNoise: 0.15)
        sim.feed(seconds: 2)
        for s in test {
            let before = sim.events.count
            sim.feed(seconds: 1, taps: [(0.3, s, gain)])
            if sim.events.count > before, let ev = sim.events.last { live.append((Features.extract(g: ev.g, a: ev.a), s.label)) }
        }
    }
    func jitter(_ s: TapSample, _ rng: inout SplitMix64) -> [Double] {
        let shift = Int.random(in: -6...6, using: &rng), noise = Double.random(in: 0.05...0.2, using: &rng)
        let gain = Double.random(in: 0.7...1.4, using: &rng)
        func roll(_ rows: [[Double]], _ k: Double, _ rng: inout SplitMix64) -> [[Double]] {
            var out: [[Double]] = []
            for i in rows.indices {
                let j = min(max(i - shift, 0), rows.count - 1)
                out.append(rows[j].map { $0 * gain + Double.random(in: -k...k, using: &rng) })
            }
            return out
        }
        let g = roll(s.g, noise, &rng), a = roll(s.a, noise / 300, &rng)
        return Features.extract(g: g, a: a)
    }
    for copies in [0, 2, 4, 8] {
        let X = train.map { Features.extract(g: $0.g, a: $0.a) }, L = train.map(\.label)
        let aug = train.map { Augment.variants(of: $0, copies: copies) }
        _ = jitter
        for kind in [ModelKind.logreg, .knn, .centroid] {
            T.run("\(kind.title), \(copies) augmented copies per tap") {
                let m = ZoneModel(kind: kind, X: X, labels: L, augmented: aug)
                var c = 0, w = 0, r = 0
                for x in live {
                    let p = m.predict(x.f, rejectFactor: 2)
                    if p.rejected != nil { r += 1 } else if p.label == x.label { c += 1 } else { w += 1 }
                }
                let direct = test.filter { m.predict(Features.extract(g: $0.g, a: $0.a), rejectFactor: 2).label == $0.label }.count
                T.note("live: correct \(c), wrong \(w), rejected \(r) of \(live.count) · clean held-out \(direct)/30")
            }
        }
    }
}
