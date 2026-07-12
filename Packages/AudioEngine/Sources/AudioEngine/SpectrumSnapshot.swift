public struct SpectrumSnapshot: Equatable, Sendable {
    public let bands: SIMD8<Float>
    public let rms: Float
    public let peak: Float

    public static let zero = SpectrumSnapshot(
        bands: .zero,
        rms: 0,
        peak: 0
    )

    public init(
        bands: SIMD8<Float>,
        rms: Float,
        peak: Float
    ) {
        self.bands = SIMD8<Float>(
            Self.normalized(bands[0]),
            Self.normalized(bands[1]),
            Self.normalized(bands[2]),
            Self.normalized(bands[3]),
            Self.normalized(bands[4]),
            Self.normalized(bands[5]),
            Self.normalized(bands[6]),
            Self.normalized(bands[7])
        )
        self.rms = Self.normalized(rms)
        self.peak = Self.normalized(peak)
    }

    private static func normalized(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }
}
