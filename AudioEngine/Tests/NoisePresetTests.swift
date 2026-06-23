import Testing
@testable import AudioEngine

@Test func whiteIsFlat() {
    #expect(NoisePreset.white.gains == [Float](repeating: 0, count: 8))
}

@Test func eachPresetHasEightBands() {
    for p in [NoisePreset.white, .pink, .brown] {
        #expect(p.gains.count == 8)
    }
}

@Test func pinkAndBrownTiltDownWithFrequency() {
    // Low frequencies louder than high → non-increasing across bands.
    for p in [NoisePreset.pink, .brown] {
        let g = p.gains
        for i in 1..<g.count {
            #expect(g[i] <= g[i - 1])
        }
    }
}

@Test func brownTiltsSteeperThanPink() {
    // At the top band, brown is attenuated at least as much as pink.
    #expect(NoisePreset.brown.gains.last! <= NoisePreset.pink.gains.last!)
}

@Test func gainsAreClamped() {
    for p in [NoisePreset.white, .pink, .brown] {
        for g in p.gains { #expect(g >= -24 && g <= 12) }
    }
}
