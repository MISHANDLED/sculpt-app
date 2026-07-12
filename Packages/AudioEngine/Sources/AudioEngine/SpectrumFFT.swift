import Accelerate
import Foundation

final class SpectrumFFT {
    static let sampleCount = 4_096

    private static let log2Count = vDSP_Length(12)
    private static let centers: [Double] = [
        60, 125, 250, 500, 1_000, 2_000, 4_000, 8_000
    ]

    private let setup: FFTSetup
    private let bandRanges: [Range<Int>]
    private let coherentGain: Float
    private var timeDomain = [Float](repeating: 0, count: sampleCount)
    private var window = [Float](repeating: 0, count: sampleCount)
    private var windowed = [Float](repeating: 0, count: sampleCount)
    private var splitReal = [Float](repeating: 0, count: sampleCount / 2)
    private var splitImag = [Float](repeating: 0, count: sampleCount / 2)
    private var powers = [Float](repeating: 0, count: sampleCount / 2)

    init?(sampleRate: Double) {
        guard sampleRate.isFinite, sampleRate >= 16_000,
              let setup = vDSP_create_fftsetup(Self.log2Count, FFTRadix(kFFTRadix2)) else {
            return nil
        }
        self.setup = setup

        vDSP_hann_window(
            &window,
            vDSP_Length(Self.sampleCount),
            Int32(vDSP_HANN_NORM)
        )
        var gain: Float = 0
        vDSP_meanv(window, 1, &gain, vDSP_Length(Self.sampleCount))
        coherentGain = gain

        let interior = zip(Self.centers, Self.centers.dropFirst()).map { pair in
            sqrt(pair.0 * pair.1)
        }
        let edges = [20.0] + interior + [min(12_000, sampleRate / 2)]
        let binWidth = sampleRate / Double(Self.sampleCount)
        bandRanges = (0..<8).map { index in
            let first = max(1, Int(ceil(edges[index] / binWidth)))
            let end = min(
                Self.sampleCount / 2,
                max(first + 1, Int(ceil(edges[index + 1] / binWidth)))
            )
            return first..<end
        }
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
    }

    func analyze(
        _ samples: UnsafeBufferPointer<Float>
    ) -> SpectrumSnapshot {
        guard samples.count == Self.sampleCount else { return .zero }

        for index in 0..<Self.sampleCount {
            let value = samples[index]
            timeDomain[index] = value.isFinite ? value : 0
        }

        var rms: Float = 0
        var peak: Float = 0
        vDSP_rmsqv(timeDomain, 1, &rms, vDSP_Length(Self.sampleCount))
        vDSP_maxmgv(timeDomain, 1, &peak, vDSP_Length(Self.sampleCount))
        vDSP_vmul(
            timeDomain,
            1,
            window,
            1,
            &windowed,
            1,
            vDSP_Length(Self.sampleCount)
        )

        splitReal.withUnsafeMutableBufferPointer { real in
            splitImag.withUnsafeMutableBufferPointer { imaginary in
                var split = DSPSplitComplex(
                    realp: real.baseAddress!,
                    imagp: imaginary.baseAddress!
                )
                windowed.withUnsafeBytes { bytes in
                    let complex = bytes.bindMemory(to: DSPComplex.self)
                    vDSP_ctoz(
                        complex.baseAddress!,
                        2,
                        &split,
                        1,
                        vDSP_Length(Self.sampleCount / 2)
                    )
                }
                vDSP_fft_zrip(
                    setup,
                    &split,
                    1,
                    Self.log2Count,
                    FFTDirection(FFT_FORWARD)
                )
                vDSP_zvmags(
                    &split,
                    1,
                    &powers,
                    1,
                    vDSP_Length(Self.sampleCount / 2)
                )
            }
        }

        // vDSP_fft_zrip doubles the conventional positive-frequency
        // coefficient, so N × coherent gain recovers peak amplitude.
        let amplitudeScale = 1 / (Float(Self.sampleCount) * coherentGain)
        var powerScale = amplitudeScale * amplitudeScale
        vDSP_vsmul(
            powers,
            1,
            &powerScale,
            &powers,
            1,
            vDSP_Length(Self.sampleCount / 2)
        )

        var bands = SIMD8<Float>.zero
        for (index, range) in bandRanges.enumerated() {
            var mean: Float = 0
            powers.withUnsafeBufferPointer { buffer in
                vDSP_meanv(
                    buffer.baseAddress! + range.lowerBound,
                    1,
                    &mean,
                    vDSP_Length(range.count)
                )
            }
            bands[index] = Self.mapPower(mean, floorDB: -72, ceilingDB: -12)
        }

        return SpectrumSnapshot(
            bands: bands,
            rms: Self.mapAmplitude(rms, floorDB: -60, ceilingDB: -12),
            peak: Self.mapAmplitude(peak, floorDB: -48, ceilingDB: -6)
        )
    }

    private static func mapPower(
        _ power: Float,
        floorDB: Float,
        ceilingDB: Float
    ) -> Float {
        let dB = 10 * log10(max(power, 1e-12))
        return normalized(dB, floorDB: floorDB, ceilingDB: ceilingDB)
    }

    private static func mapAmplitude(
        _ amplitude: Float,
        floorDB: Float,
        ceilingDB: Float
    ) -> Float {
        let dB = 20 * log10(max(amplitude, 1e-6))
        return normalized(dB, floorDB: floorDB, ceilingDB: ceilingDB)
    }

    private static func normalized(
        _ dB: Float,
        floorDB: Float,
        ceilingDB: Float
    ) -> Float {
        min(1, max(0, (dB - floorDB) / (ceilingDB - floorDB)))
    }
}
