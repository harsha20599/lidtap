import Foundation

/// Feature extraction and classifiers, checked against the Python/scikit-learn prototype.
@MainActor
func mlTests() {
    T.suite = "ML"
    print("\n▶ ML pipeline")
    let ds = T.loadDataset()
    let refData = try! Data(contentsOf: T.fixtures.appendingPathComponent("python_reference.json"))
    let ref = try! JSONSerialization.jsonObject(with: refData) as! [String: Any]
    let X = ds.samples.map { Features.extract(g: $0.g, a: $0.a) }
    let labels = ds.samples.map(\.label)

    T.run("features match Python for all 60 real taps") {
        let py = ref["features"] as! [[Double]]
        T.expect(X.count == py.count, "count \(X.count) vs \(py.count)")
        var worst = 0.0, worstAt = (0, 0)
        for i in 0..<min(X.count, py.count) {
            T.expect(X[i].count == py[i].count, "dims \(X[i].count) vs \(py[i].count)")
            for j in 0..<min(X[i].count, py[i].count) {
                let d = abs(X[i][j] - py[i][j]) / max(1, abs(py[i][j]))
                if d > worst { worst = d; worstAt = (i, j) }
            }
        }
        T.note("max relative difference \(String(format: "%.2e", worst)) at sample \(worstAt.0) feature \(worstAt.1)")
        T.expect(worst < 1e-6, "feature mismatch \(worst) at \(worstAt)")
    }

    T.run("features are finite and strength-invariant") {
        for x in X { T.expect(x.allSatisfy(\.isFinite), "non-finite feature") }
        let s = ds.samples[0]
        let scaled = Features.extract(g: s.g.map { $0.map { $0 * 3 } }, a: s.a.map { $0.map { $0 * 3 } })
        // Only the log tap-strength feature (index 16) may change when a tap is 3x stronger.
        for j in 0..<X[0].count where j != 16 { T.expect(abs(scaled[j] - X[0][j]) < 1e-9, "feature \(j) changed with tap strength") }
        T.expect(abs(scaled[16] - X[0][16] - log(3)) < 1e-9, "strength feature should shift by log 3")
    }

    T.run("degenerate windows don't crash or produce NaN") {
        let zeros = Array(repeating: [0.0, 0, 0], count: TapDetector.n)
        T.expect(Features.extract(g: zeros, a: zeros).allSatisfy(\.isFinite), "all-zero window gave non-finite features")
        let spike = (0..<TapDetector.n).map { $0 == TapDetector.n - 1 ? [50.0, -50, 50] : [0.0, 0, 0] }
        T.expect(Features.extract(g: spike, a: spike).allSatisfy(\.isFinite), "edge spike gave non-finite features")
    }

    let train = labels.indices.filter { $0 % 2 == 0 }, test = labels.indices.filter { $0 % 2 == 1 }
    let pyPreds = ref["split_predictions"] as! [String: [String]]
    for kind in ModelKind.allCases {
        T.run("\(kind.title) agrees with scikit-learn on a fixed split") {
            let p = fitPredict(kind, X: train.map { X[$0] }, labels: train.map { labels[$0] }, test: test.map { X[$0] })
            let agree = zip(p, pyPreds[kind.rawValue]!).filter { $0 == $1 }.count
            let acc = zip(p, test).filter { $0 == labels[$1] }.count
            T.note("agreement \(agree)/\(p.count), accuracy \(acc)/\(p.count)")
            // kNN and nearest centroid are deterministic and must match exactly; logistic regression
            // uses a different optimiser (Adam vs L-BFGS) so allow a couple of borderline taps.
            T.expect(agree >= (kind == .logreg ? p.count - 3 : p.count), "\(kind.rawValue): only \(agree)/\(p.count) agree")
        }
    }

    T.run("numpy-style percentile") {
        for c in ref["percentiles"] as! [[String: Any]] {
            let v = (c["values"] as! [NSNumber]).map(\.doubleValue), q = (c["q"] as! NSNumber).doubleValue
            let want = (c["result"] as! NSNumber).doubleValue
            T.expect(abs(percentile(v, q) - want) < 1e-12, "percentile(\(v), \(q)) = \(percentile(v, q)), want \(want)")
        }
    }

    T.run("cross-validated evaluation on real taps") {
        let r = Evaluator.evaluate(X: X, labels: labels, grid: ds.grid)
        T.expect(r.layouts == ["Full grid", "Left / right", "Top / bottom"], "2×2 layouts \(r.layouts)")
        for s in r.scores {
            let a = s.accuracy[Layouts.full] ?? 0
            T.note("\(s.kind.title): \(Int(a * 100))%")
            T.expect(a >= 0.85, "\(s.kind.title) full-grid accuracy \(a) below 85%")
        }
        T.expect(r.confusion?.flatMap { $0 }.reduce(0, +) == 60, "confusion matrix must count every tap")
        T.expect(!r.learning.isEmpty && r.learning.last!.accuracy > r.learning.first!.accuracy - 0.05, "learning curve should rise")
    }

    T.run("layout mappings for 2×2, 2×3 and 3×3") {
        let g33 = Layouts.all(for: Grid(rows: 3, cols: 3))
        T.expect(g33.map(\.0) == ["Full grid", "Columns", "Left / right", "Rows", "Top / bottom", "Corners"], "3×3 layouts \(g33.map(\.0))")
        let lr = g33.first { $0.0 == "Left / right" }!.1
        T.expect(lr("z0") == "L" && lr("z2") == "R" && lr("z1") == nil && lr("z4") == nil && lr(noiseLabel) == noiseLabel, "3×3 left/right drops the middle column")
        let corners = g33.first { $0.0 == "Corners" }!.1
        T.expect(corners("z0") == "q00" && corners("z8") == "q11" && corners("z4") == nil, "3×3 corners")
        let g23 = Layouts.all(for: Grid(rows: 2, cols: 3))
        let tb = g23.first { $0.0 == "Top / bottom" }!.1
        T.expect(tb("z1") == "T" && tb("z4") == "B", "2×3 top/bottom")
    }

    T.run("open-set rejection: training taps accepted, junk rejected") {
        let m = ZoneModel(kind: .logreg, X: X, labels: labels)
        let accepted = X.indices.filter { m.predict(X[$0], rejectFactor: 2).rejected == nil }.count
        T.expect(accepted == X.count, "\(X.count - accepted) training taps rejected")
        var rejected = 0
        for seed in 0..<40 {
            var rng = SplitMix64(seed: UInt64(seed))
            let g = (0..<TapDetector.n).map { _ in (0..<3).map { _ in Double.random(in: -3...3, using: &rng) } }
            let a = (0..<TapDetector.n).map { _ in (0..<3).map { _ in Double.random(in: -0.01...0.01, using: &rng) } }
            if m.predict(Features.extract(g: g, a: a), rejectFactor: 2).rejected != nil { rejected += 1 }
        }
        T.note("random-noise windows rejected: \(rejected)/40")
        T.expect(rejected >= 36, "only \(rejected)/40 random windows rejected")
    }

    T.run("noise class predictions are always rejected") {
        var Xn = X, Ln = labels
        for seed in 0..<15 {
            var rng = SplitMix64(seed: UInt64(seed + 100))
            let g = (0..<TapDetector.n).map { i in (0..<3).map { _ in Double.random(in: -1...1, using: &rng) * (i > 24 ? 4 : 0.2) } }
            Xn.append(Features.extract(g: g, a: g.map { $0.map { $0 / 300 } }))
            Ln.append(noiseLabel)
        }
        let m = ZoneModel(kind: .knn, X: Xn, labels: Ln)
        let p = m.predict(Xn.last!, rejectFactor: 100)
        T.expect(p.label == noiseLabel && p.rejected != nil, "noise sample predicted \(p.label), rejected=\(String(describing: p.rejected))")
    }

    T.run("training speed on a large dataset (3×3 × 30 taps + noise)") {
        var bigX: [[Double]] = [], bigL: [String] = []
        for i in 0..<300 { bigX.append(X[i % X.count].map { $0 + Double.random(in: -0.05...0.05) }); bigL.append(i < 270 ? zoneLabel(i % 9) : noiseLabel) }
        // Augmented variants, as the app trains (cheap stand-ins: jittered copies of the features).
        let aug = bigX.map { x in (0..<Augment.copies).map { _ in x.map { $0 + Double.random(in: -0.05...0.05) } } }
        let t0 = Date()
        _ = Evaluator.evaluate(X: bigX, labels: bigL, grid: Grid(rows: 3, cols: 3), augmented: aug)
        let dt = Date().timeIntervalSince(t0)
        T.note(String(format: "full evaluation with ×%d augmentation (3 models × 6 layouts + learning curve): %.2f s", Augment.copies + 1, dt))
        T.expect(dt < 30, "evaluation took \(dt) s")
        let t1 = Date()
        let m = ZoneModel(kind: .logreg, X: bigX, labels: bigL, augmented: aug)
        let fit = Date().timeIntervalSince(t1)
        let t2 = Date()
        for x in bigX.prefix(100) { _ = m.predict(x, rejectFactor: 2) }
        let per = Date().timeIntervalSince(t2) / 100 * 1000
        T.note(String(format: "fit %.2f s, predict %.2f ms per tap", fit, per))
        T.expect(per < 10, "prediction too slow: \(per) ms")
    }
}
