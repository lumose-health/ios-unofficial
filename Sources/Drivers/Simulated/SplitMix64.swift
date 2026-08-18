/// A small, fixed-algorithm pseudorandom generator, so the same seed produces
/// the same sequence on every platform and every Swift version — unlike
/// `SystemRandomNumberGenerator`, which makes no such promise and is not
/// meant to.
///
/// SplitMix64 is the public-domain generator behind Java's
/// `SplittableRandom` and many seeded test harnesses. It is not
/// cryptographic, and nothing here needs it to be — this generates a
/// plausible-looking trace, not a secret.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A uniform value drawn from `range`.
    mutating func uniform(in range: ClosedRange<Double>) -> Double {
        let fraction = Double(next() >> 11) * (1.0 / Double(1 << 53))   // [0, 1)
        return range.lowerBound + fraction * (range.upperBound - range.lowerBound)
    }
}
