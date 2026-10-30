import Foundation

/// Features for one tap window (160 x 3 gyro + 160 x 3 accel, trigger at index 24).
///
/// Everything is normalised by tap strength so soft and firm taps in one zone look alike. The sign of
/// the twist at its peak carries left/right; the twist/shake ratio and decay carry near/far from the hinge.
/// This mirrors `lidtap/features.py` exactly so data recorded by either tool trains the same model.
enum Features {
    static let fs = TapDetector.fs
    static let n = TapDetector.n, trig = TapDetector.trig
    static let templateLength = 64, templateStep = 4
    static let bands: [(Double, Double)] = [(0, 40), (40, 80), (80, 160), (160, 400)]
    static let handCount = 22
    static let templateCount = (templateLength / templateStep) * 3
    static let count = handCount + templateCount
    /// Applied after standardisation so the long waveform template does not drown the hand-made features.
    static let weights: [Double] = Array(repeating: 1, count: handCount) + Array(repeating: 0.35, count: templateCount)

    private static let hann: [Double] = (0..<n).map { 0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(n - 1)) }

    private static func norm(_ r: [Double]) -> Double {
        let s: Double = r[0] * r[0] + r[1] * r[1] + r[2] * r[2]
        return s.squareRoot()
    }

    private static func axisEnergy(_ x: [[Double]]) -> [Double] {
        var e = [1e-12, 1e-12, 1e-12]
        for row in x { for ax in 0..<3 { e[ax] += row[ax] * row[ax] } }
        return e
    }

    private static func argmax(_ x: ArraySlice<Double>) -> Int {
        var best = x.startIndex
        for i in x.indices where x[i] > x[best] { best = i }
        return best
    }

    private static func bandEnergies(_ x: [Double]) -> [Double] {
        let half = x.count / 2
        var e = Array(repeating: 1e-12, count: bands.count)
        for k in 0...half {
            var re = 0.0, im = 0.0
            for (i, v) in x.enumerated() {
                let w = v * hann[i]
                let ph = -2 * Double.pi * Double(k * i) / Double(x.count)
                re += w * cos(ph)
                im += w * sin(ph)
            }
            let f = Double(k) * fs / Double(x.count)
            if let b = bands.firstIndex(where: { f >= $0.0 && f < $0.1 }) { e[b] += re * re + im * im }
        }
        let total = e.reduce(0, +)
        return e.map { log($0 / total) }
    }

    /// Where the tap starts: the first sample at 25% of the window's peak twist. Anchoring on this instead of
    /// the trigger crossing makes the features independent of the trigger threshold (and so of the noise level).
    static func onset(_ gm: [Double]) -> Int {
        let span = gm[0..<min(gm.count, 120)]
        guard let peak = span.max(), peak > 0 else { return trig }
        return span.firstIndex { $0 >= 0.25 * peak } ?? trig
    }

    static func extract(g: [[Double]], a: [[Double]]) -> [Double] {
        let gm = g.map(norm), am = a.map(norm)
        let o = onset(gm)
        let k = argmax(gm[o..<min(o + 64, gm.count)])
        let gp = max(gm[k], 1e-6)
        let ka = argmax(am[max(o - 8, 0)..<min(o + 64, am.count)])
        let ap = max(am[ka], 1e-9)

        var f: [Double] = []
        f.reserveCapacity(count)
        f += g[k].map { $0 / gp }                                  // twist direction at its peak (signed)

        var net = [0.0, 0.0, 0.0], absSum = 1e-9
        for row in g[max(o - 8, 0)..<min(o + 32, n)] {
            for ax in 0..<3 {
                net[ax] += row[ax]
                absSum += abs(row[ax])
            }
        }
        f += net.map { $0 / absSum }                               // net early rotation per axis

        let eg = axisEnergy(g), ea = axisEnergy(a)
        let egTotal = eg.reduce(0, +), eaTotal = ea.reduce(0, +)
        f += eg.map { $0 / egTotal }                               // how twist energy splits across axes
        f += a[ka].map { $0 / ap }                                 // shake direction at its peak
        f += ea.map { $0 / eaTotal }
        f += [log(gp / ap), log(gp)]                               // twist per unit shake; tap strength

        var decay = n - k
        for j in k..<n where gm[j] < 0.25 * gp { decay = j - k; break }
        f.append(Double(decay) / fs * 1000 / 50)
        f += bandEnergies(gm)

        let rows = templateLength / templateStep
        let first = k >= 8 ? k - 8 : 0
        for r in 0..<rows {
            let i = first + r * templateStep
            if i < n && i < first + templateLength {
                f += g[i].map { $0 / gp }
            } else {
                f += [0, 0, 0]
            }
        }
        return f
    }
}
