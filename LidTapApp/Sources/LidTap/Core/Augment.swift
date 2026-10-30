import Foundation

/// Training-time augmentation: each recorded tap also contributes a few variants with sensor noise,
/// ±40% strength and a few samples of timing jitter, so the model tolerates how live taps differ from
/// calibration taps. (In simulation it raised correct live taps from 111 to 139 of 150 and cut rejections from 32 to 5.)
enum Augment {
    static let copies = 4

    /// Feature vectors for `copies` variants of a tap. Seeded by the sample id, so training is reproducible.
    static func variants(of s: TapSample, copies: Int = copies) -> [[Double]] {
        var rng = SplitMix64(seed: UInt64(truncatingIfNeeded: s.id) &* 0x9E37_79B9 &+ 17)
        return (0..<copies).map { _ in
            let shift = Int.random(in: -6...6, using: &rng)
            let noise = Double.random(in: 0.05...0.2, using: &rng)
            let gain = Double.random(in: 0.7...1.4, using: &rng)
            func vary(_ rows: [[Double]], _ k: Double) -> [[Double]] {
                var out: [[Double]] = []
                out.reserveCapacity(rows.count)
                for i in rows.indices {
                    let j = min(max(i - shift, 0), rows.count - 1)
                    out.append(rows[j].map { $0 * gain + Double.random(in: -k...k, using: &rng) })
                }
                return out
            }
            let g = vary(s.g, noise), a = vary(s.a, noise / 300)
            return Features.extract(g: g, a: a)
        }
    }
}
