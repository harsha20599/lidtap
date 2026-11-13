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
        let m = ZoneModel(kind: kind, X: train.map { Features.extract(g: $0.g, a: $0.a) }, labels: train.map(\.label), augmented: train.map { Augment.variants(of: $0) })  // trained as the app does
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
            for factor in [1.0, 1.2, 1.3, 1.4, 1.5, 2.0, 3.0, 5.0] {
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

/// Replays a raw recording against a calibration, through the detector and the app exactly as shipped.
/// Stretches named like a zone ("z0") are taps on that zone; every other stretch (typing, moving things on the
/// desk, a lap) is a disturbance, where anything acted on is a false tap.
///   LIDTAP_REPLAY_STREAM=/path/to/recording (without .json/.bin)  LIDTAP_REPLAY_DATASET=/path/to/dataset.json  build/LidTapTests replay
///   LIDTAP_REPLAY_LEFT_RIGHT=1  regroup the calibration into two sides first
///   LIDTAP_REPLAY_NO_INPUT=1    ignore the recording's keyboard and pointer events (as if the app could not see them)
///   LIDTAP_REPLAY_PASSES=2      play it twice and report the second time, after the app has learned from the first
///   LIDTAP_REPLAY_REJECT=1.5, LIDTAP_REPLAY_CONFIDENCE=0.8   try other "ignore unfamiliar taps" and "act only when this sure" settings
@MainActor
func replayDiag() {
    T.suite = "Diagnostics"
    print("\n▶ Replay a recording against a calibration")
    let env = ProcessInfo.processInfo.environment
    guard let streamPath = env["LIDTAP_REPLAY_STREAM"], let datasetPath = env["LIDTAP_REPLAY_DATASET"] else {
        print("  set LIDTAP_REPLAY_STREAM and LIDTAP_REPLAY_DATASET")
        return
    }
    T.run("the recording, as the app would handle it") {
        let url = URL(fileURLWithPath: streamPath)
        let stream = try T.loadStream(url.lastPathComponent, in: url.deletingLastPathComponent())
        let dataset = try JSONDecoder().decode(Dataset.self, from: Data(contentsOf: URL(fileURLWithPath: datasetPath)))
        let h = AppHarness(name: "replay", dataset: dataset)
        guard h.train() else { return T.fail("no model") }
        let was = dataset.grid
        if env["LIDTAP_REPLAY_LEFT_RIGHT"] != nil {
            h.app.regroupLeftRight()
            guard T.wait(30, { h.app.report?.grid == .leftRight && !h.app.isTraining }) else { return T.fail("no two-side model") }
        }
        T.note(String(format: "trained %@ on %d taps (%@), cross-validated %d%%, strength limit %.2f", h.app.activeKind?.title ?? "-", h.app.report?.sampleCount ?? 0,
                      h.app.grid.title, Int(((h.app.accuracy ?? 0) * 100).rounded()), h.app.minTapStrength))
        if let v = env["LIDTAP_REPLAY_REJECT"].flatMap(Double.init) { h.app.config.rejectFactor = v }
        if let v = env["LIDTAP_REPLAY_CONFIDENCE"].flatMap(Double.init) { h.app.config.minConfidence = v }
        T.note("scores: " + (h.app.report?.scores.map { "\($0.kind.rawValue) \(Int((($0.accuracy[Layouts.full] ?? 0) * 100).rounded()))%" }.joined(separator: ", ") ?? "-"))
        var r = replay(stream, in: h, calibratedOn: was, withInputs: env["LIDTAP_REPLAY_NO_INPUT"] == nil)
        for _ in 1..<(Int(env["LIDTAP_REPLAY_PASSES"] ?? "") ?? 1) {
            T.note("first pass: \(r.correct) correct, \(r.wrong) wrong, \(r.declined) declined, \(r.falseTaps) false taps; learned \(h.app.dataset.learnedCount) non-taps")
            h.app.retrain()
            T.sleep(0.5)
            _ = T.wait(30) { !h.app.isTraining }
            T.note("retrained: \(h.app.activeKind?.title ?? "-") on \(h.app.report?.sampleCount ?? 0) samples, \(Int(((h.app.accuracy ?? 0) * 100).rounded()))%")
            r = replay(stream, in: h, calibratedOn: was, withInputs: env["LIDTAP_REPLAY_NO_INPUT"] == nil)
        }
        for line in r.lines { T.note(line) }
        T.note("taps: \(r.correct) correct, \(r.wrong) wrong, \(r.declined) declined of \(r.correct + r.wrong + r.declined) · false taps in the disturbances: \(r.falseTaps)")
    }
}

struct ReplayResult {
    var correct = 0, wrong = 0, declined = 0, falseTaps = 0
    var lines: [String] = []
}

/// Feeds a recording to the detector and its events, with the recording's keyboard and pointer input, to the app.
@MainActor
func replay(_ stream: RawStream, in h: AppHarness, calibratedOn was: Grid? = nil, withInputs: Bool = true) -> ReplayResult {
    let sim = StreamSim(settings: h.app.config.detector)
    sim.feed(stream)
    let base = MachClock.now() + 1000   // recording time on the app's clock, clear of anything real
    let start = Date()
    var result = ReplayResult()
    var nextInput = 0
    let sides = was != nil && was != h.app.grid && h.app.grid == .leftRight
    for seg in stream.segments {
        let zone = zoneIndex(seg.name)
        let want = zone.map { z in sides ? zoneLabel(was!.half(ofZone: z) ?? -1) : seg.name }
        var tally: [String: Int] = [:]
        for e in sim.events where e.time >= seg.start && e.time < seg.end {
            // The app handles a tap just after its window ends, knowing the input up to then.
            while withInputs, nextInput < stream.inputs.count, stream.inputs[nextInput].time <= e.time + TapDetector.post + 0.02 {
                if let kind = InputMonitor.Kind(rawValue: stream.inputs[nextInput].kind) { h.app.input.record(kind, at: base + stream.inputs[nextInput].time) }
                nextInput += 1
            }
            h.performed.removeAll()
            h.app.handle(TapEvent(id: e.id, time: base + e.time, date: start.addingTimeInterval(e.time), g: e.g, a: e.a, peakG: e.peakG, peakA: e.peakA,
                                  lid: e.lid, threshold: e.threshold, noise: e.noise, gated: e.gated, gateDetail: e.gateDetail, preMotion: e.preMotion))
            if h.app.privacyGuard.isActive { h.app.privacyGuard.release() }
            guard let r = h.app.lastRecord, r.id == e.id else { continue }
            let kind: String
            switch r.outcome {
            case .acted:
                if let want { kind = r.label == want ? "correct" : "wrong (\(r.label ?? "?"))" } else { kind = "FALSE TAP (\(r.label ?? "?"))" }
                if want == nil { result.falseTaps += 1 } else if r.label == want { result.correct += 1 } else { result.wrong += 1 }
            case .rejected:
                kind = r.detail.hasPrefix("Too soft") ? "too soft" : r.detail
                if want != nil { result.declined += 1 }
            default:
                kind = r.detail
                if want != nil { result.declined += 1 }
            }
            tally[kind, default: 0] += 1
        }
        let text = tally.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: ", ")
        result.lines.append("\(seg.name) (\(Int(seg.end - seg.start)) s): \(text.isEmpty ? "nothing" : text)")
    }
    return result
}
