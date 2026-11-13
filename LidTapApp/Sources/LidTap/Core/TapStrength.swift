import Foundation

/// Second-order Butterworth high-pass on a 3-axis stream. At 30 Hz it keeps the jolt of a fingertip landing
/// (the impact band) and drops gravity, hand pressure and the slow sway of a desk or a lap.
struct ImpactFilter {
    static let cutoff = 30.0

    private let b0: Double, b1: Double, b2: Double, a1: Double, a2: Double
    private var z1 = SIMD3<Double>.zero, z2 = SIMD3<Double>.zero
    private var primed = false

    init(fc: Double = ImpactFilter.cutoff, fs: Double = TapDetector.fs) {
        let w = 2 * Double.pi * fc / fs
        let alpha = sin(w) / 2.0.squareRoot(), c = cos(w), a0 = 1 + alpha
        b0 = (1 + c) / 2 / a0
        b1 = -(1 + c) / a0
        b2 = b0
        a1 = -2 * c / a0
        a2 = (1 - alpha) / a0
    }

    mutating func callAsFunction(_ x: SIMD3<Double>) -> SIMD3<Double> {
        // Start settled on the first sample: the raw accelerometer carries 1 g of gravity, and starting
        // from zero would ring like a tap of a thousand milli-g.
        if !primed {
            primed = true
            z1 = -b0 * x
            z2 = b2 * x
        }
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }
}

/// How hard a tap landed, and how hard it must land before LidTap records or acts on it.
///
/// A tap shows up two ways: it twists the base (gyroscope, °/s) and it jolts it (accelerometer, g). How the
/// two split depends on the Mac. A light flick twists a 13" MacBook Air 5 to 10 °/s; the same flick twists a
/// 14" MacBook Pro 0.3 to 1.5 °/s, the size of the gyroscope's own noise, yet jolts it 5 to 30 milli-g, twenty
/// to a hundred times the accelerometer's noise. So strength is whichever is larger: the twist in °/s, or the
/// jolt at 3 milli-g per unit (3 mg stands as far above a resting accelerometer as 1 °/s does above a resting
/// gyroscope). On an Air the twist usually decides, on a Pro the jolt does, and one scale fits both.
///
/// The limit is half of this Mac's typical tap in its weakest zone, never above 3.5 (below which the Air's
/// accuracy fell from 95% to 56%) and never below 1, where taps sink into the sensors' background. Half, because
/// people tap more lightly in daily use than while calibrating: on a 14" Pro calibrated at a typical 2.9 in its
/// weakest zone, a two-thirds limit refused one live tap in seven, and every one of those between half and two
/// thirds was read as the right zone.
enum TapStrength {
    static let ceiling = 3.5
    static let floor = 1.0
    static let fraction = 0.5
    /// Jolt (g, impact band) that counts like 1 °/s of twist.
    static let impactPerUnit = 0.003
    /// Samples at the start of a window to skip while the impact filter settles.
    private static let settle = 8

    /// Peak jolt (g) of a tap window's accelerometer rows in the impact band.
    static func impact(_ a: [[Double]]) -> Double {
        var filter = ImpactFilter()
        var best = 0.0
        for (i, r) in a.enumerated() where r.count >= 3 {
            let y = filter(SIMD3(r[0], r[1], r[2]))
            if i >= settle { best = max(best, (y * y).sum().squareRoot()) }
        }
        return best
    }

    static func strength(twist: Double, impact: Double) -> Double { max(twist, impact / impactPerUnit) }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let n = sorted.count
        return n % 2 == 1 ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2
    }

    /// `strengths`: strengths of the taps aimed at zones on this Mac, recorded or refused.
    static func learned(from strengths: [Double]) -> Double {
        guard !strengths.isEmpty else { return floor }
        return min(ceiling, max(floor, fraction * median(strengths)))
    }

    /// The same, zone by zone. Taps far from the sensor land softer (on a 14" Pro a top corner jolts the base a
    /// fifth as much as a bottom corner), so the limit follows the weakest zone's typical tap: a limit taken from
    /// all taps together would refuse most of that zone's. A zone counts once it has three taps.
    static func learned(byZone strengths: [String: [Double]]) -> Double {
        let settled = strengths.values.filter { $0.count >= 3 }
        guard let weakest = settled.map(median).min() else { return learned(from: strengths.values.flatMap { $0 }) }
        return min(ceiling, max(floor, fraction * weakest))
    }
}
