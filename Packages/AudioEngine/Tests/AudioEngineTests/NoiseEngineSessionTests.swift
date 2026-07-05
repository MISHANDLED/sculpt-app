import Testing
import AVFoundation
@testable import AudioEngine

@Suite("Session deactivation policy")
struct NoiseEngineSessionTests {

    @Test func manualStopDeactivatesSession() {
        let engine = NoiseEngine()
        engine.stop()
        #expect(engine._lastStopDeactivatedSession == true)
    }

    @Test func interruptionStopKeepsSessionActive() {
        let engine = NoiseEngine()
        engine._applyInterruption(type: .began, options: [])
        #expect(engine._lastStopDeactivatedSession == false)
    }
}
