import Foundation

/// Built-in noise colors expressed as 8-band EQ tilts over white noise.
/// white/pink/brown are derived from a per-octave slope referenced to the
/// lowest band (60 Hz = 0 dB). grey/speechBlocker use explicit starter tables
/// (tune by ear later). All gains clamp to the engine's -24…+12 dB range.
public enum NoisePreset: CaseIterable {
    case white, pink, brown, grey, speechBlocker

    public var gains: [Float] {
        switch self {
        case .white, .pink, .brown:
            return tiltGains(slopePerOctave: slopePerOctave)
        case .grey:
            // U-shaped, approximating an inverse equal-loudness contour.
            return Self.clamp([6, 3, 0, -2, -2, 0, 4, 8])
        case .speechBlocker:
            // Energy concentrated in the speech band (~300–3000 Hz) to mask conversation.
            return Self.clamp([-8, -4, 3, 6, 6, 3, -4, -8])
        }
    }

    /// dB per octave of attenuation for the slope-derived colors.
    private var slopePerOctave: Float {
        switch self {
        case .white: return 0
        case .pink:  return 3
        case .brown: return 6
        case .grey, .speechBlocker: return 0   // unused (table-driven)
        }
    }

    private func tiltGains(slopePerOctave: Float) -> [Float] {
        let freqs = AudioEngineModule.bandFrequencies
        guard let base = freqs.first else { return [] }
        return freqs.map { f in
            let octaves = log2(f / base)
            return Self.clampOne(-slopePerOctave * octaves)
        }
    }

    private static func clamp(_ gains: [Float]) -> [Float] { gains.map(clampOne) }
    private static func clampOne(_ g: Float) -> Float { min(12, max(-24, g)) }
}
