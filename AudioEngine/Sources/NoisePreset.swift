import Foundation

/// Built-in noise colors expressed as 8-band EQ tilts over white noise.
/// Referenced to the lowest band (60 Hz = 0 dB); higher bands attenuate.
/// EQ-tilt approximates true pink/brown but is the product's real mechanism.
public enum NoisePreset: CaseIterable {
    case white, pink, brown

    /// dB per octave of attenuation, relative to the lowest band.
    private var slopePerOctave: Float {
        switch self {
        case .white: return 0
        case .pink:  return 3
        case .brown: return 6
        }
    }

    public var gains: [Float] {
        let freqs = AudioEngineModule.bandFrequencies
        guard let base = freqs.first else { return [] }
        return freqs.map { f in
            let octaves = log2(f / base)            // 0 at base, grows upward
            let g = -slopePerOctave * octaves
            return min(12, max(-24, g))
        }
    }
}
