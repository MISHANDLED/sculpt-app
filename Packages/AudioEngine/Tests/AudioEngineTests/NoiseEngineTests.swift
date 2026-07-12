import Testing
@testable import AudioEngine

@MainActor
@Test func hasEightBandsAtExpectedFrequencies() {
    let e = NoiseEngine()
    #expect(e.bandCount == 8)
    let expected: [Float] = [60, 125, 250, 500, 1000, 2000, 4000, 8000]
    for i in 0..<e.bandCount {
        #expect(e.centerFrequency(band: i) == expected[i])
    }
}

@MainActor
@Test func setGainClampsToRange() {
    let e = NoiseEngine()
    e.setGain(band: 0, dB: 999)
    #expect(e.gain(band: 0) == 12)
    e.setGain(band: 0, dB: -999)
    #expect(e.gain(band: 0) == -24)
    e.setGain(band: 0, dB: 5)
    #expect(e.gain(band: 0) == 5)
}

@MainActor
@Test func applyPresetSetsAllBands() {
    let e = NoiseEngine()
    e.apply(.white)
    for i in 0..<e.bandCount { #expect(e.gain(band: i) == 0) }
    e.apply(.brown)
    #expect(e.gain(band: 7) < e.gain(band: 0))
}

@MainActor
@Test func masterVolumeClampsAndDrivesMixer() {
    let engine = NoiseEngine()
    engine.masterVolume = 1.5
    #expect(engine.masterVolume == 1.0)
    engine.masterVolume = -0.2
    #expect(engine.masterVolume == 0.0)
    engine.masterVolume = 0.6
    #expect(abs(engine._mixerOutputVolume - 0.6) < 0.001)
}
