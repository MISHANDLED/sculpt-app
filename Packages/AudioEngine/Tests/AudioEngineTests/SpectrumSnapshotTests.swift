import Testing
@testable import AudioEngine

@Suite("Spectrum snapshot")
struct SpectrumSnapshotTests {
    @Test func zeroContainsOnlyZeros() {
        #expect(SpectrumSnapshot.zero.bands == .zero)
        #expect(SpectrumSnapshot.zero.rms == 0)
        #expect(SpectrumSnapshot.zero.peak == 0)
    }

    @Test func initializerClampsFiniteValues() {
        let snapshot = SpectrumSnapshot(
            bands: SIMD8<Float>(-1, 0, 0.25, 0.5, 0.75, 1, 2, 100),
            rms: -0.5,
            peak: 1.5
        )

        #expect(snapshot.bands == SIMD8<Float>(0, 0, 0.25, 0.5, 0.75, 1, 1, 1))
        #expect(snapshot.rms == 0)
        #expect(snapshot.peak == 1)
    }

    @Test func initializerReplacesNonFiniteValuesWithZero() {
        let snapshot = SpectrumSnapshot(
            bands: SIMD8<Float>(
                .nan, .infinity, -.infinity, 0.2, 0.4, 0.6, 0.8, 1
            ),
            rms: .nan,
            peak: .infinity
        )

        #expect(snapshot.bands == SIMD8<Float>(0, 0, 0, 0.2, 0.4, 0.6, 0.8, 1))
        #expect(snapshot.rms == 0)
        #expect(snapshot.peak == 0)
    }
}
