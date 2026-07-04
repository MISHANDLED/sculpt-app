import Testing
@testable import AudioEngine

@Suite("Fade curve")
struct FadeTests {

    @Test func linearRampToExactZero() {
        #expect(fadeCurve(from: 1, steps: 4) == [0.75, 0.5, 0.25, 0])
    }

    @Test func emptyForNonPositiveSteps() {
        #expect(fadeCurve(from: 1, steps: 0).isEmpty)
        #expect(fadeCurve(from: 1, steps: -3).isEmpty)
    }

    @Test func lastElementAlwaysZero() {
        #expect(fadeCurve(from: 0.6, steps: 7).last == 0)
    }

    @Test func fadeStopFallsBackToImmediateWhenNotPlaying() {
        let engine = NoiseEngine()
        engine.stop(fadeDuration: 5)          // not playing → immediate path
        #expect(engine._lastStopDeactivatedSession == true)
        #expect(engine.isPlaying == false)
    }

    @Test func stepCountRoundsInsteadOfTruncating() {
        #expect(NoiseEngine.fadeStepCount(for: 0.15) == 3)
        #expect(NoiseEngine.fadeStepCount(for: 0.05) == 1)
        #expect(NoiseEngine.fadeStepCount(for: 0) == 1)
    }

    @Test func stopRestoresMasterVolume() {
        let engine = NoiseEngine()
        engine.masterVolume = 0.6
        engine.stop()
        #expect(abs(engine._mixerOutputVolume - 0.6) < 0.001)
    }
}
