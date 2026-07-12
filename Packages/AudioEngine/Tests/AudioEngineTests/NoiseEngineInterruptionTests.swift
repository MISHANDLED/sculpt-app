import AVFoundation
import Foundation
import Testing
@testable import AudioEngine

/// Regression tests for the interruption auto-resume wiring in NoiseEngine.
///
/// The pure-function tests in AudioSessionPolicyTests verify `interruptionAction`
/// in isolation, but they cannot catch the bug where `handleInterruption` passes
/// the post-stop `isPlaying` (always false) instead of the pre-interruption value.
/// These tests exercise the stored-flag seam added to NoiseEngine to prove the
/// wiring is correct without requiring a live AVAudioSession.
@MainActor
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

    @Test func interruptionNotificationHopsToMainActor() async {
        let center = NotificationCenter()
        let engine = NoiseEngine(notificationCenter: center)
        engine._setPlayingForTesting(true)

        await Task.detached {
            center.post(
                name: AVAudioSession.interruptionNotification,
                object: nil,
                userInfo: [
                    AVAudioSessionInterruptionTypeKey:
                        AVAudioSession.InterruptionType.began.rawValue
                ]
            )
        }.value
        for _ in 0..<20 where engine.isPlaying { await Task.yield() }
        #expect(!engine.isPlaying)
        #expect(engine._lastStopDeactivatedSession == false)
    }
}
