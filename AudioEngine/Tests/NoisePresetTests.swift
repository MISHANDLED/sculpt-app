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

@Test func greyIsUShaped() {
    let g = NoisePreset.grey.gains
    #expect(g.count == 8)
    #expect(g.first! > g[3])   // low edge boosted above the mids
    #expect(g.last! > g[4])    // high edge boosted above the mids
}

@Test func speechBlockerBoostsMidBands() {
    let g = NoisePreset.speechBlocker.gains
    #expect(g.count == 8)
    #expect(g[3] > g.first!)   // 500 Hz boosted above the low edge
    #expect(g[4] > g.last!)    // 1 kHz boosted above the high edge
}

@Test func newPresetsAreClamped() {
    for p in [NoisePreset.grey, .speechBlocker] {
        for g in p.gains { #expect(g >= -24 && g <= 12) }
    }
}

@Test func whiteHasNoMakeupGain() {
    #expect(NoisePreset.white.makeupGain == 0)
}

@Test func darkerPresetsGetMoreMakeup() {
    #expect(NoisePreset.brown.makeupGain > NoisePreset.pink.makeupGain)
    #expect(NoisePreset.pink.makeupGain > 0)
}

@Test func makeupClampedToTwelveDB() {
    for p in NoisePreset.allCases {
        #expect(p.makeupGain.magnitude <= 12)
    }
}

@Test func applySetsGlobalGainFromPreset() {
    let engine = NoiseEngine()
    engine.apply(.brown)
    #expect(abs(engine.globalGain - NoisePreset.brown.makeupGain) < 0.01)
    engine.apply(.white)
    #expect(engine.globalGain == 0)
}
