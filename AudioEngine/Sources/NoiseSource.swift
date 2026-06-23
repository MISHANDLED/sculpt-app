/// Real-time-safe white-noise source. Value semantics, no allocation.
/// `next()` averages 3 xorshift draws (central-limit smoothing) so the
/// noise sounds less "digital" than a single uniform sample.
public struct NoiseSource {
    private var state: UInt64

    public init(seed: UInt64) {
        // xorshift64 stalls on 0 — substitute a fixed nonzero seed.
        state = seed != 0 ? seed : 0x9E37_79B9_7F4A_7C15
    }

    public mutating func next() -> Float {
        var sum: Float = 0
        for _ in 0..<3 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            // top 24 bits → [0,1), then map to [-1,1]
            let u = Float(state >> 40) * (1.0 / Float(1 << 24))
            sum += u * 2 - 1
        }
        return sum / 3
    }
}
