import Foundation

struct Grid: Codable, Equatable, Hashable {
    var rows: Int
    var cols: Int
    var count: Int { rows * cols }
    var title: String { "\(rows)×\(cols)" }

    static let presets = [Grid(rows: 2, cols: 2), Grid(rows: 2, cols: 3), Grid(rows: 3, cols: 3)]
}

func zoneLabel(_ i: Int) -> String { "z\(i)" }
func zoneIndex(_ label: String) -> Int? { label.hasPrefix("z") ? Int(label.dropFirst()) : nil }

struct Prediction: Equatable {
    var label: String
    var confidence: Double
    var novelty: Double
    var rejected: String?
}

/// Trained zone classifier with open-set rejection.
struct ZoneModel {
    let kind: ModelKind
    let classes: [String]
    let scaler: Standardizer
    let classifier: ZoneClassifier
    let Z: [[Double]]
    let y: [Int]
    let radius: [Double]

    /// `augmented[i]` holds extra feature vectors for sample i (see Augment); they train the classifier and
    /// join the nearest-neighbour search, but the "usual spacing" radius comes from the real taps only
    /// (near-duplicate variants would shrink it and reject everything slightly new).
    init(kind: ModelKind, X: [[Double]], labels: [String], augmented: [[[Double]]] = []) {
        self.kind = kind
        classes = Array(Set(labels)).sorted()
        let index = Dictionary(uniqueKeysWithValues: classes.enumerated().map { ($1, $0) })
        var allX = X, allLabels = labels
        for (i, variants) in augmented.enumerated() where i < labels.count {
            allX += variants
            allLabels += Array(repeating: labels[i], count: variants.count)
        }
        let scaler = Standardizer(fit: allX)
        let Z = allX.map(scaler.transform)
        let y = allLabels.map { index[$0]! }
        self.scaler = scaler
        self.Z = Z
        self.y = y
        classifier = makeClassifier(kind, Z: Z, y: y, classes: classes.count)
        // Typical spacing inside each class: 95th percentile of nearest same-class neighbour distance.
        let realZ = Array(Z.prefix(X.count)), realY = Array(y.prefix(X.count))
        var radius: [Double] = []
        for c in classes.indices {
            let members = realZ.indices.filter { realY[$0] == c }.map { realZ[$0] }
            guard members.count >= 3 else { radius.append(.infinity); continue }
            let nearest = members.indices.map { i in
                members.indices.filter { $0 != i }.map { dist(members[i], members[$0]) }.min() ?? .infinity
            }
            let r = percentile(nearest, 95)
            radius.append(r > 0 ? r : .infinity)
        }
        self.radius = radius
    }

    func predict(_ features: [Double], rejectFactor: Double) -> Prediction {
        let z = scaler.transform(features)
        let p = classifier.probabilities(z)
        let c = p.indices.max { p[$0] < p[$1] }!
        let nearest = Z.indices.filter { y[$0] == c }.map { dist(Z[$0], z) }.min() ?? .infinity
        let novelty = radius[c].isFinite ? nearest / radius[c] : 0
        var rejected: String?
        if classes[c] == noiseLabel {
            rejected = "Looks like a bump, not a tap"
        } else if novelty > rejectFactor {
            rejected = "Unfamiliar tap"
        }
        return Prediction(label: classes[c], confidence: p[c], novelty: novelty, rejected: rejected)
    }
}

private func dist(_ a: [Double], _ b: [Double]) -> Double {
    var s = 0.0
    for i in 0..<a.count { let d = a[i] - b[i]; s += d * d }
    return s.squareRoot()
}

/// numpy-style linear-interpolation percentile.
func percentile(_ values: [Double], _ q: Double) -> Double {
    let s = values.sorted()
    guard !s.isEmpty else { return .nan }
    let pos = q / 100 * Double(s.count - 1)
    let lo = Int(pos.rounded(.down)), hi = min(lo + 1, s.count - 1)
    return s[lo] + (s[hi] - s[lo]) * (pos - Double(lo))
}

// MARK: - Evaluation

struct ModelScore: Identifiable, Equatable {
    var kind: ModelKind
    var accuracy: [String: Double]  // layout name -> cross-validated accuracy
    var id: ModelKind { kind }
}

struct ModelReport: Equatable {
    var sampleCount: Int
    var grid: Grid
    var labels: [String]
    var layouts: [String]
    var scores: [ModelScore]
    var best: ModelKind
    var confusion: [[Int]]?
    var learning: [(n: Int, accuracy: Double)]
    var trainedAt: Date

    static func == (a: ModelReport, b: ModelReport) -> Bool { a.trainedAt == b.trainedAt && a.sampleCount == b.sampleCount }

    func accuracy(_ kind: ModelKind, _ layout: String = Layouts.full) -> Double? {
        scores.first { $0.kind == kind }?.accuracy[layout]
    }
}

enum Layouts {
    static let full = "Full grid"

    /// Coarser layouts a grid can be merged into: name -> label mapper (nil drops the sample).
    static func all(for grid: Grid) -> [(String, (String) -> String?)] {
        let rows = grid.rows, cols = grid.cols
        func by(_ f: @escaping (Int, Int) -> String?) -> (String) -> String? {
            { label in label == noiseLabel ? label : zoneIndex(label).flatMap { f($0 / cols, $0 % cols) } }
        }
        func half(_ n: Int, _ i: Int) -> Int? { (n % 2 == 1 && i == n / 2) ? nil : (Double(i) >= Double(n) / 2 ? 1 : 0) }
        var out: [(String, (String) -> String?)] = [(full, { $0 })]
        if cols >= 3 { out.append(("Columns", by { _, c in "col\(c)" })) }
        if cols >= 2 { out.append(("Left / right", by { _, c in half(cols, c).map { $0 == 0 ? "L" : "R" } })) }
        if rows >= 3 { out.append(("Rows", by { r, _ in "row\(r)" })) }
        if rows >= 2 { out.append(("Top / bottom", by { r, _ in half(rows, r).map { $0 == 0 ? "T" : "B" } })) }
        if rows >= 2, cols >= 2, !(rows == 2 && cols == 2) {
            out.append(("Corners", by { r, c in
                guard let hr = half(rows, r), let hc = half(cols, c) else { return nil }
                return "q\(hr)\(hc)"
            }))
        }
        return out
    }
}

enum Evaluator {
    /// Stratified k-fold predictions (k = min(5, smallest class)), or nil if any class has < 2 samples.
    static func crossValidate(_ kind: ModelKind, X: [[Double]], labels: [String], augmented: [[[Double]]]? = nil) -> [String]? {
        var byClass: [String: [Int]] = [:]
        for (i, l) in labels.enumerated() { byClass[l, default: []].append(i) }
        guard byClass.count >= 2, let smallest = byClass.values.map(\.count).min(), smallest >= 2 else { return nil }
        let k = min(5, smallest)
        var rng = SplitMix64(seed: 0)
        var fold = Array(repeating: 0, count: labels.count)
        for key in byClass.keys.sorted() {
            for (j, i) in byClass[key]!.shuffled(using: &rng).enumerated() { fold[i] = j % k }
        }
        var pred = Array(repeating: "", count: labels.count)
        for f in 0..<k {
            let train = labels.indices.filter { fold[$0] != f }, test = labels.indices.filter { fold[$0] == f }
            let out = fitPredict(kind, X: train.map { X[$0] }, labels: train.map { labels[$0] }, test: test.map { X[$0] },
                                 augmented: augmented.map { aug in train.map { aug[$0] } })
            for (i, p) in zip(test, out) { pred[i] = p }
        }
        return pred
    }

    static func learningCurve(_ kind: ModelKind, X: [[Double]], labels: [String], augmented: [[[Double]]]? = nil, repeats: Int = 4) -> [(n: Int, accuracy: Double)] {
        var byClass: [String: [Int]] = [:]
        for (i, l) in labels.enumerated() { byClass[l, default: []].append(i) }
        let smallest = byClass.values.map(\.count).min() ?? 0
        var out: [(Int, Double)] = []
        for n in [2, 3, 5, 8, 10, 15, 20, 30, 40] where n < smallest {
            var accs: [Double] = []
            for rep in 0..<repeats {
                var rng = SplitMix64(seed: UInt64(rep + 1))
                var train: [Int] = [], test: [Int] = []
                for key in byClass.keys.sorted() {
                    let idx = byClass[key]!.shuffled(using: &rng)
                    train += idx.prefix(n)
                    test += idx.dropFirst(n)
                }
                let pred = fitPredict(kind, X: train.map { X[$0] }, labels: train.map { labels[$0] }, test: test.map { X[$0] },
                                      augmented: augmented.map { aug in train.map { aug[$0] } })
                accs.append(Double(zip(pred, test).filter { $0 == labels[$1] }.count) / Double(test.count))
            }
            out.append((n, accs.reduce(0, +) / Double(accs.count)))
        }
        return out
    }

    /// Cross-validated scores per model and layout. Augmented variants are only ever added to training folds.
    static func evaluate(X: [[Double]], labels: [String], grid: Grid, augmented: [[[Double]]]? = nil) -> ModelReport {
        let layouts = Layouts.all(for: grid)
        var scores: [ModelScore] = []
        var fullPreds: [ModelKind: [String]] = [:]
        for kind in ModelKind.allCases {
            var acc: [String: Double] = [:]
            for (name, map) in layouts {
                let keep = labels.indices.filter { map(labels[$0]) != nil }
                let mapped = keep.map { map(labels[$0])! }
                if let p = crossValidate(kind, X: keep.map { X[$0] }, labels: mapped, augmented: augmented.map { aug in keep.map { aug[$0] } }) {
                    acc[name] = Double(zip(p, mapped).filter { $0 == $1 }.count) / Double(mapped.count)
                    if name == Layouts.full { fullPreds[kind] = p }
                }
            }
            scores.append(ModelScore(kind: kind, accuracy: acc))
        }
        // Ties go to the earlier kind in ModelKind.allCases (logistic regression first).
        let best = scores.max { ($0.accuracy[Layouts.full] ?? -1) < ($1.accuracy[Layouts.full] ?? -1) }?.kind ?? .logreg
        let ordered = Array(Set(labels)).sorted { a, b in
            if (a == noiseLabel) != (b == noiseLabel) { return b == noiseLabel }
            return (zoneIndex(a) ?? 0) < (zoneIndex(b) ?? 0)
        }
        var confusion: [[Int]]?
        if let p = fullPreds[best] {
            let idx = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($1, $0) })
            var cm = Array(repeating: Array(repeating: 0, count: ordered.count), count: ordered.count)
            for (t, q) in zip(labels, p) { cm[idx[t]!][idx[q]!] += 1 }
            confusion = cm
        }
        return ModelReport(sampleCount: labels.count, grid: grid, labels: ordered, layouts: layouts.map(\.0),
                           scores: scores, best: best, confusion: confusion,
                           learning: fullPreds[best] == nil ? [] : learningCurve(best, X: X, labels: labels, augmented: augmented),
                           trainedAt: Date())
    }
}
