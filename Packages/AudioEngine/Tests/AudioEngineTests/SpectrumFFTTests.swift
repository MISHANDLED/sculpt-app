import Foundation
import Testing
@testable import AudioEngine

enum SpectrumTestSignal {
    static func sine(
        frequency: Double,
        sampleRate: Double,
        amplitude: Float = 0.5
    ) -> [Float] {
        (0..<SpectrumFFT.sampleCount).map { index in
            amplitude * sin(2 * .pi * Float(frequency) * Float(index) / Float(sampleRate))
        }
    }

    static func mixed(
        frequencies: [Double],
        sampleRate: Double,
        amplitude: Float = 0.25
    ) -> [Float] {
        (0..<SpectrumFFT.sampleCount).map { index in
            frequencies.reduce(Float.zero) { sum, frequency in
                sum + amplitude * sin(
                    2 * .pi * Float(frequency) * Float(index) / Float(sampleRate)
                )
            }
        }
    }

    static func deterministicNoise() -> [Float] {
        var state: UInt64 = 0x1234_5678_9ABC_DEF0
        return (0..<SpectrumFFT.sampleCount).map { _ in
            state = state &* 6_364_136_223_846_793_005 &+ 1
            let unit = Float(state >> 40) / Float(1 << 24)
            return (unit * 2 - 1) * 0.4
        }
    }

    static func analyze(
        _ samples: [Float],
        sampleRate: Double = 44_100
    ) -> SpectrumSnapshot {
        let fft = SpectrumFFT(sampleRate: sampleRate)!
        return samples.withUnsafeBufferPointer { fft.analyze($0) }
    }
}

@Suite("Spectrum FFT")
struct SpectrumFFTTests {
    private let centers: [Double] = [60, 125, 250, 500, 1_000, 2_000, 4_000, 8_000]

    @Test func silenceProducesZeroSnapshot() {
        let samples = [Float](repeating: 0, count: SpectrumFFT.sampleCount)
        #expect(SpectrumTestSignal.analyze(samples) == .zero)
    }

    @Test func eachEQCenterDominatesNonAdjacentBands() {
        for (index, center) in centers.enumerated() {
            let snapshot = SpectrumTestSignal.analyze(
                SpectrumTestSignal.sine(frequency: center, sampleRate: 44_100)
            )
            let distant = (0..<8)
                .filter { abs($0 - index) > 1 }
                .map { snapshot.bands[$0] }
                .max() ?? 0
            #expect(snapshot.bands[index] > distant + 0.10)
        }
    }

    @Test func geometricBoundaryToneActivatesAdjacentBands() {
        let boundary = sqrt(500.0 * 1_000.0)
        let snapshot = SpectrumTestSignal.analyze(
            SpectrumTestSignal.sine(frequency: boundary, sampleRate: 44_100)
        )
        let nonAdjacent = [snapshot.bands[0], snapshot.bands[1], snapshot.bands[2],
                           snapshot.bands[6], snapshot.bands[7]].max() ?? 0
        #expect(max(snapshot.bands[3], snapshot.bands[4]) > nonAdjacent + 0.10)
        #expect(min(snapshot.bands[3], snapshot.bands[4]) > 0)
    }

    @Test func mixedTonesActivateCorrespondingBands() {
        let snapshot = SpectrumTestSignal.analyze(
            SpectrumTestSignal.mixed(
                frequencies: [125, 2_000],
                sampleRate: 44_100
            )
        )
        #expect(snapshot.bands[1] > snapshot.bands[4])
        #expect(snapshot.bands[5] > snapshot.bands[3])
    }

    @Test func deterministicNoiseProducesFiniteBoundedValues() {
        let snapshot = SpectrumTestSignal.analyze(
            SpectrumTestSignal.deterministicNoise()
        )
        for index in 0..<8 {
            #expect(snapshot.bands[index].isFinite)
            #expect((0...1).contains(snapshot.bands[index]))
        }
        #expect(snapshot.rms.isFinite && (0...1).contains(snapshot.rms))
        #expect(snapshot.peak.isFinite && (0...1).contains(snapshot.peak))
    }

    @Test func knownAmplitudeProducesExpectedRMSAndPeakMappings() {
        let samples = (0..<SpectrumFFT.sampleCount).map { $0.isMultiple(of: 2) ? Float(0.25) : -0.25 }
        let snapshot = SpectrumTestSignal.analyze(samples)
        let expectedRMS = Float((20 * log10(0.25) + 60) / 48)
        let expectedPeak = Float((20 * log10(0.25) + 48) / 42)
        #expect(abs(snapshot.rms - expectedRMS) < 0.001)
        #expect(abs(snapshot.peak - expectedPeak) < 0.001)
    }

    @Test func binCenteredSineHasStableNormalization() {
        let frequency = 44_100.0 * 64.0 / Double(SpectrumFFT.sampleCount)
        let snapshot = SpectrumTestSignal.analyze(
            SpectrumTestSignal.sine(
                frequency: frequency,
                sampleRate: 44_100,
                amplitude: 1
            )
        )
        #expect(snapshot.bands[3] > 0.70)
    }

    @Test func repeatedAnalysisIsDeterministic() {
        let fft = SpectrumFFT(sampleRate: 44_100)!
        let samples = SpectrumTestSignal.sine(frequency: 1_000, sampleRate: 44_100)
        let first = samples.withUnsafeBufferPointer { fft.analyze($0) }
        let second = samples.withUnsafeBufferPointer { fft.analyze($0) }
        #expect(first == second)
    }

    @Test func semanticBandsMatchAt44100And48000() {
        let at44100 = SpectrumTestSignal.analyze(
            SpectrumTestSignal.sine(frequency: 1_000, sampleRate: 44_100),
            sampleRate: 44_100
        )
        let at48000 = SpectrumTestSignal.analyze(
            SpectrumTestSignal.sine(frequency: 1_000, sampleRate: 48_000),
            sampleRate: 48_000
        )
        let max44100 = (0..<8).map { at44100.bands[$0] }.max()
        let max48000 = (0..<8).map { at48000.bands[$0] }.max()
        #expect(at44100.bands[4] == max44100)
        #expect(at48000.bands[4] == max48000)
    }

    @Test func shortInputProducesZero() {
        let fft = SpectrumFFT(sampleRate: 44_100)!
        let samples = [Float](repeating: 1, count: 128)
        let snapshot = samples.withUnsafeBufferPointer { fft.analyze($0) }
        #expect(snapshot == .zero)
    }

    @Test func nonFiniteInputCannotEscapeSnapshot() {
        var samples = SpectrumTestSignal.sine(frequency: 500, sampleRate: 44_100)
        samples[10] = .nan
        samples[20] = .infinity
        let snapshot = SpectrumTestSignal.analyze(samples)
        #expect((0..<8).allSatisfy { snapshot.bands[$0].isFinite })
        #expect(snapshot.rms.isFinite)
        #expect(snapshot.peak.isFinite)
    }
}
