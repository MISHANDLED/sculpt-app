/// Real-time-safe white-noise source. Value semantics, no allocation.
/// `next()` averages 3 xorshift draws (central-limit smoothing) so the
/// noise sounds less "digital" than a single uniform sample.
public struct NoiseSource {
    private var state: UInt64
    private static let amplitude: Float = 0.15  // headroom below full-scale so post-EQ boosts don't clip

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
        return (sum / 3) * Self.amplitude
    }
}

/// Two-channel noise with a controlled stereo width. Fully independent noise
/// in each ear can sound diffuse and fatiguing over long listening sessions;
/// retaining a smaller independent side component keeps the image spacious
/// without producing a hard, disconnected headphone presentation.
struct StereoNoiseSource {
    private var left: NoiseSource
    private var right: NoiseSource

    /// Side level relative to the mono component. The normalization keeps RMS
    /// energy approximately equal to two independent sources.
    private static let sideLevel: Float = 0.45
    private static let normalization: Float = 1.289_277

    init(leftSeed: UInt64, rightSeed: UInt64) {
        left = NoiseSource(seed: leftSeed)
        right = NoiseSource(seed: rightSeed)
    }

    mutating func next() -> (left: Float, right: Float) {
        let rawLeft = left.next()
        let rawRight = right.next()
        let mid = (rawLeft + rawRight) * 0.5
        let side = (rawLeft - rawRight) * 0.5 * Self.sideLevel
        return (
            (mid + side) * Self.normalization,
            (mid - side) * Self.normalization
        )
    }
}
