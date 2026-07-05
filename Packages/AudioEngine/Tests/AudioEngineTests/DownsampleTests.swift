import Testing
@testable import AudioEngine

@Test func downsampleEmptyReturnsEmpty() {
    #expect(downsample([], to: 128) == [])
}

@Test func downsampleBlockAverages() {
    #expect(downsample([1, 2, 3, 4], to: 2) == [1.5, 3.5])
}

@Test func downsampleShorterThanCountReturnsInput() {
    #expect(downsample([1, 2, 3], to: 5) == [1, 2, 3])
}

@Test func downsampleClampsCountToAtLeastOne() {
    #expect(downsample([1, 2, 3, 4], to: 0) == [2.5])
}
