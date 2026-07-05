import Testing
@testable import AudioEngine

@Suite("Media services reset recovery")
struct NoiseEngineMediaResetTests {

    @Test func rebuildPreservesGainsGlobalAndBandCount() {
        let engine = NoiseEngine()
        engine.setGain(band: 2, dB: 5)
        engine.setGlobalGain(3)
        engine._recoverFromMediaServicesReset()
        #expect(engine.bandCount == 8)
        #expect(engine.gain(band: 2) == 5)
        #expect(abs(engine.globalGain - 3) < 0.001)
        #expect(engine.isPlaying == false)
    }

    @Test func rebuildClearsStaleScopeTapFlag() {
        let engine = NoiseEngine()
        engine._installScopeTap()
        engine._recoverFromMediaServicesReset()
        #expect(engine.isScopeTapInstalled == false)
    }
}
