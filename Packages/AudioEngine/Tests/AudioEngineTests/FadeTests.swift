import Testing
@testable import AudioEngine
import Foundation

@MainActor
@Suite("Fade curve")
struct FadeTests {

    @Test func immediateRestartDuringFadeSkipsSessionAndKeepsGraphRunning() async throws {
        let session = FadeSessionCoordinatorProbe()
        let graph = FadePlaybackGraphProbe()
        graph.running = true
        let engine = NoiseEngine(
            notificationCenter: NotificationCenter(),
            audioSessionCoordinator: session,
            playbackGraphHooks: graph.hooks
        )
        engine.spectrumAnalysisEnabled = false
        engine._setPlayingForTesting(false)
        engine.isFading = true

        try await engine.start()

        #expect(engine.isPlaying)
        #expect(engine.isPlaybackRequested)
        #expect(!engine.isFading)
        #expect(graph.startCount == 0)
        #expect(graph.stopCount == 0)
        #expect(session.activationCount == 0)
    }

    @Test func linearRampToExactZero() {
        #expect(Fade.curve(from: 1, steps: 4) == [0.75, 0.5, 0.25, 0])
    }

    @Test func emptyForNonPositiveSteps() {
        #expect(Fade.curve(from: 1, steps: 0).isEmpty)
        #expect(Fade.curve(from: 1, steps: -3).isEmpty)
    }

    @Test func lastElementAlwaysZero() {
        #expect(Fade.curve(from: 0.6, steps: 7).last == 0)
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

    // MARK: - masterVolume vs. in-flight fade (Finding 2)

    @Test func masterVolumeSkipsMixerWriteWhileFading() {
        let engine = NoiseEngine()
        engine.masterVolume = 0.8
        engine.isFading = true
        engine.masterVolume = 0.3
        #expect(abs(engine._mixerOutputVolume - 0.8) < 0.001)   // no zipper mid-fade
        #expect(engine.masterVolume == 0.3)                     // stored value still updates
    }

    @Test func masterVolumeAppliesAfterFadeEnds() {
        let engine = NoiseEngine()
        engine.masterVolume = 0.8
        engine.isFading = true
        engine.masterVolume = 0.3
        engine.isFading = false
        engine.masterVolume = 0.5
        #expect(abs(engine._mixerOutputVolume - 0.5) < 0.001)
    }

    @Test func stopClearsIsFadingFlag() {
        let engine = NoiseEngine()
        engine.isFading = true
        engine.stop()
        #expect(engine.isFading == false)
    }
}

private final class FadeSessionCoordinatorProbe: AudioSessionCoordinating,
    @unchecked Sendable
{
    private let lock = NSLock()
    private(set) var activationCount = 0

    func activate() async throws {
        lock.withLock { activationCount += 1 }
    }

    func requestInactive(_ policy: AudioSessionInactivePolicy) {}
    func waitUntilIdle() async {}
}

@MainActor
private final class FadePlaybackGraphProbe: @unchecked Sendable {
    var running = false
    var startCount = 0
    var stopCount = 0

    var hooks: NoiseEnginePlaybackGraphHooks {
        NoiseEnginePlaybackGraphHooks(
            isRunning: { [weak self] _ in self?.running == true },
            start: { [weak self] _ in
                self?.startCount += 1
                self?.running = true
            },
            stop: { [weak self] _ in
                self?.stopCount += 1
                self?.running = false
            }
        )
    }
}
