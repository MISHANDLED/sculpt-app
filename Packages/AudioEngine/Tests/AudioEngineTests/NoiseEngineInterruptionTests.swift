import Testing
@testable import AudioEngine

/// Regression tests for the interruption auto-resume wiring in NoiseEngine.
///
/// The pure-function tests in AudioSessionPolicyTests verify `interruptionAction`
/// in isolation, but they cannot catch the bug where `handleInterruption` passes
/// the post-stop `isPlaying` (always false) instead of the pre-interruption value.
/// These tests exercise the stored-flag seam added to NoiseEngine to prove the
/// wiring is correct without requiring a live AVAudioSession.
@Suite("NoiseEngine interruption resume wiring")
struct NoiseEngineInterruptionTests {

    @Test func resumesAfterInterruptionWhenWasPlaying() {
        let engine = NoiseEngine()
        // Simulate: engine was playing when interruption began.
        engine._setWasPlayingBeforeInterruption(true)
        // With shouldResume and was playing → should resume.
        #expect(engine._resumeDecisionForEndedInterruption(options: .shouldResume) == true)
    }

    @Test func doesNotResumeAfterInterruptionWhenWasNotPlaying() {
        let engine = NoiseEngine()
        // Simulate: engine was NOT playing when interruption began.
        engine._setWasPlayingBeforeInterruption(false)
        // Even with shouldResume, should not resume if wasn't playing.
        #expect(engine._resumeDecisionForEndedInterruption(options: .shouldResume) == false)
    }

    @Test func doesNotResumeWithoutShouldResumeFlag() {
        let engine = NoiseEngine()
        engine._setWasPlayingBeforeInterruption(true)
        // shouldResume flag absent → no resume even if was playing.
        #expect(engine._resumeDecisionForEndedInterruption(options: []) == false)
    }
}
