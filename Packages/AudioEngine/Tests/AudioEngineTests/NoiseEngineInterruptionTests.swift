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

    private func makeEngine(
        session: EngineSessionCoordinatorProbe,
        graph: PlaybackGraphProbe
    ) -> NoiseEngine {
        let engine = NoiseEngine(
            notificationCenter: NotificationCenter(),
            audioSessionCoordinator: session,
            playbackGraphHooks: graph.hooks
        )
        engine.spectrumAnalysisEnabled = false
        return engine
    }

    @Test func pendingStartInterruptedThenResumesExactlyOnce() async throws {
        let session = EngineSessionCoordinatorProbe()
        let graph = PlaybackGraphProbe()
        let engine = makeEngine(session: session, graph: graph)
        let pending = Task { try await engine.start() }
        #expect(await waitForActivation(session))

        await engine._applyInterruption(type: .began, options: [])
        session.completeNext(.success(()))
        await #expect(throws: CancellationError.self) { try await pending.value }

        let resume = Task {
            await engine._applyInterruption(
                type: .ended,
                options: .shouldResume
            )
        }
        #expect(await waitForActivation(session))
        session.completeNext(.success(()))
        await resume.value
        #expect(engine.isPlaying)
        #expect(session.activationCount() == 2)

        await engine._applyInterruption(type: .ended, options: .shouldResume)
        #expect(session.activationCount() == 2)
    }

    @Test func explicitStopBetweenBeginAndEndPreventsResume() async {
        let session = EngineSessionCoordinatorProbe()
        let graph = PlaybackGraphProbe()
        let engine = makeEngine(session: session, graph: graph)
        engine._setPlayingForTesting(true)

        await engine._applyInterruption(type: .began, options: [])
        engine.stop()
        await engine._applyInterruption(type: .ended, options: .shouldResume)

        #expect(!engine.isPlaying)
        #expect(session.activationCount() == 0)
    }

    @Test func routeLossBetweenBeginAndEndPreventsResume() async {
        let session = EngineSessionCoordinatorProbe()
        let graph = PlaybackGraphProbe()
        let engine = makeEngine(session: session, graph: graph)
        engine._setPlayingForTesting(true)

        await engine._applyInterruption(type: .began, options: [])
        engine._applyRouteChange(reason: .oldDeviceUnavailable)
        await engine._applyInterruption(type: .ended, options: .shouldResume)

        #expect(!engine.isPlaying)
        #expect(session.activationCount() == 0)
        #expect(session.policies().last == .deactivate)
    }

    @Test func newBeginSupersedesAwaitedResume() async {
        let session = EngineSessionCoordinatorProbe()
        let graph = PlaybackGraphProbe()
        let engine = makeEngine(session: session, graph: graph)
        engine._setPlayingForTesting(true)
        await engine._applyInterruption(type: .began, options: [])

        let resume = Task {
            await engine._applyInterruption(type: .ended, options: .shouldResume)
        }
        #expect(await waitForActivation(session))
        await engine._applyInterruption(type: .began, options: [])
        session.completeNext(.success(()))
        await resume.value

        #expect(!engine.isPlaying)
        #expect(!engine.isPlaybackRequested)
        #expect(session.activationCount() == 1)
    }

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
