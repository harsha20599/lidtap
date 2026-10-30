import Foundation

let noiseLabel = "noise"

enum ModelKind: String, Codable, CaseIterable, Identifiable {
    case logreg, knn, centroid
    var id: String { rawValue }
    var title: String {
        switch self {
        case .logreg: "Logistic regression"
        case .knn: "Nearest neighbours"
        case .centroid: "Nearest centroid"
        }
    }
}

/// Deterministic RNG so cross-validation results are stable between runs.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Standardise each feature, then apply the feature-group weights.
struct Standardizer {
    var mean: [Double], scale: [Double]

    init(fit X: [[Double]]) {
        let d = X.first?.count ?? 0, n = Double(max(X.count, 1))
        let mu = (0..<d).map { j in X.reduce(0) { $0 + $1[j] } / n }
        mean = mu
        scale = (0..<d).map { j in
            let s = (X.reduce(0) { $0 + ($1[j] - mu[j]) * ($1[j] - mu[j]) } / n).squareRoot()
            return s > 1e-12 ? s : 1
        }
    }

    func transform(_ x: [Double]) -> [Double] {
        var out = [Double](repeating: 0, count: x.count)
        for i in 0..<x.count {
            let w: Double = i < Features.weights.count ? Features.weights[i] : 1
            out[i] = w * (x[i] - mean[i]) / scale[i]
        }
        return out
    }
}

protocol ZoneClassifier {
    /// Class probabilities for an already-standardised sample.
    func probabilities(_ z: [Double]) -> [Double]
}

@inline(__always) private func distance(_ a: [Double], _ b: [Double]) -> Double {
    var s = 0.0
    for i in 0..<a.count { let d = a[i] - b[i]; s += d * d }
    return s.squareRoot()
}

struct NearestNeighbours: ZoneClassifier {
    let Z: [[Double]], y: [Int], classes: Int, k = 3

    func probabilities(_ z: [Double]) -> [Double] {
        let nearest = Z.indices.map { (distance(Z[$0], z), y[$0]) }.sorted { $0.0 < $1.0 }.prefix(k)
        var votes = Array(repeating: 0.0, count: classes)
        if let exact = nearest.first(where: { $0.0 < 1e-12 }) {
            votes[exact.1] = 1
            return votes
        }
        for (d, c) in nearest { votes[c] += 1 / d }
        let total = votes.reduce(0, +)
        return votes.map { $0 / total }
    }
}

struct NearestCentroid: ZoneClassifier {
    let centroids: [[Double]]

    init(Z: [[Double]], y: [Int], classes: Int) {
        let d = Z.first?.count ?? 0
        centroids = (0..<classes).map { c in
            let members = Z.indices.filter { y[$0] == c }.map { Z[$0] }
            return (0..<d).map { j in members.reduce(0) { $0 + $1[j] } / Double(max(members.count, 1)) }
        }
    }

    func probabilities(_ z: [Double]) -> [Double] {
        let s = centroids.map { -distance($0, z) }
        let m = s.max() ?? 0
        let e = s.map { exp($0 - m) }
        let total = e.reduce(0, +)
        return e.map { $0 / total }
    }
}

/// Multinomial logistic regression with L2 (sklearn's C = 1), trained by full-batch Adam.
struct SoftmaxRegression: ZoneClassifier {
    var W: [[Double]], b: [Double]

    init(Z: [[Double]], y: [Int], classes: Int, iterations: Int = 300) {
        let n = Z.count, d = Z.first?.count ?? 0
        W = Array(repeating: Array(repeating: 0, count: d), count: classes)
        b = Array(repeating: 0, count: classes)
        let lambda = 1.0 / Double(max(n, 1))
        var mW = W, vW = W, mb = b, vb = b
        let lr = 0.05, b1 = 0.9, b2 = 0.999, eps = 1e-8
        var p = Array(repeating: 0.0, count: classes)
        for step in 1...iterations {
            var gW = Array(repeating: Array(repeating: 0.0, count: d), count: classes)
            var gb = Array(repeating: 0.0, count: classes)
            for i in 0..<n {
                let z = Z[i]
                var m = -Double.infinity
                for c in 0..<classes {
                    var s = b[c]
                    let w = W[c]
                    for j in 0..<d { s += w[j] * z[j] }
                    p[c] = s
                    m = max(m, s)
                }
                var total = 0.0
                for c in 0..<classes { p[c] = exp(p[c] - m); total += p[c] }
                for c in 0..<classes {
                    let err = p[c] / total - (y[i] == c ? 1 : 0)
                    if err == 0 { continue }
                    gb[c] += err
                    for j in 0..<d { gW[c][j] += err * z[j] }
                }
            }
            let inv = 1.0 / Double(n)
            let c1 = 1 - pow(b1, Double(step)), c2 = 1 - pow(b2, Double(step))
            for c in 0..<classes {
                for j in 0..<d {
                    let g = gW[c][j] * inv + lambda * W[c][j]
                    mW[c][j] = b1 * mW[c][j] + (1 - b1) * g
                    vW[c][j] = b2 * vW[c][j] + (1 - b2) * g * g
                    W[c][j] -= lr * (mW[c][j] / c1) / ((vW[c][j] / c2).squareRoot() + eps)
                }
                let g = gb[c] * inv
                mb[c] = b1 * mb[c] + (1 - b1) * g
                vb[c] = b2 * vb[c] + (1 - b2) * g * g
                b[c] -= lr * (mb[c] / c1) / ((vb[c] / c2).squareRoot() + eps)
            }
        }
    }

    func probabilities(_ z: [Double]) -> [Double] {
        let s = (0..<W.count).map { c in zip(W[c], z).reduce(b[c]) { $0 + $1.0 * $1.1 } }
        let m = s.max() ?? 0
        let e = s.map { exp($0 - m) }
        let total = e.reduce(0, +)
        return e.map { $0 / total }
    }
}

func makeClassifier(_ kind: ModelKind, Z: [[Double]], y: [Int], classes: Int) -> ZoneClassifier {
    switch kind {
    case .knn: NearestNeighbours(Z: Z, y: y, classes: classes)
    case .centroid: NearestCentroid(Z: Z, y: y, classes: classes)
    case .logreg: SoftmaxRegression(Z: Z, y: y, classes: classes)
    }
}

/// Fit scaler + classifier on (X, labels) plus each row's augmented variants, and predict labels for `test`.
func fitPredict(_ kind: ModelKind, X: [[Double]], labels: [String], test: [[Double]], augmented: [[[Double]]]? = nil) -> [String] {
    var X = X, labels = labels
    if let augmented {
        for (i, variants) in augmented.enumerated() { X += variants; labels += Array(repeating: labels[i], count: variants.count) }
    }
    let classes = Array(Set(labels)).sorted()
    let index = Dictionary(uniqueKeysWithValues: classes.enumerated().map { ($1, $0) })
    let scaler = Standardizer(fit: X)
    let Z = X.map(scaler.transform)
    let clf = makeClassifier(kind, Z: Z, y: labels.map { index[$0]! }, classes: classes.count)
    return test.map { x in
        let p = clf.probabilities(scaler.transform(x))
        return classes[p.indices.max { p[$0] < p[$1] }!]
    }
}
