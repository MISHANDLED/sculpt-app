import Testing
@testable import AudioEngine

@Test func downsampleEmptyReturnsEmpty() {
    #expect(Downsample.resample([], to: 128) == [])
}

@Test func downsampleBlockAverages() {
    #expect(Downsample.resample([1, 2, 3, 4], to: 2) == [1.5, 3.5])
}

@Test func downsampleShorterThanCountReturnsInput() {
    #expect(Downsample.resample([1, 2, 3], to: 5) == [1, 2, 3])
}

@Test func downsampleClampsCountToAtLeastOne() {
    #expect(Downsample.resample([1, 2, 3, 4], to: 0) == [2.5])
}
