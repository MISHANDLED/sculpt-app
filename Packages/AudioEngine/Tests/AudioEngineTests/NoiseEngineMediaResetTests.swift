import AVFoundation
import Foundation
import Testing
@testable import AudioEngine

@MainActor
private final class InvalidGraphLifecycleProbe {
    private let recorder: SpectrumLifecycleRecorder
    private(set) var graphIsValid = true
    private(set) var invalidEQAccessCount = 0

    init(recorder: SpectrumLifecycleRecorder) {
        self.recorder = recorder
    }

    var hooks: NoiseEngineGraphLifecycleHooks {
        NoiseEngineGraphLifecycleHooks(
            validateEQAccess: { [weak self] in
                guard let self else { return }
                if !graphIsValid {
                    invalidEQAccessCount += 1
                }
            },
            willReplaceGraph: { [weak self] in
                self?.recorder.record(.graphWillReplace)
            },
            didReplaceGraph: { [weak self] in
                guard let self else { return }
                graphIsValid = true
                recorder.record(.graphDidReplace)
            }
        )
    }

    func markGraphLost() {
        graphIsValid = false
    }
}

@MainActor
@Suite("Media services reset recovery")
struct NoiseEngineMediaResetTests {
    @Test func resetNotifiesRequestInvalidationAfterSystemManagedIntent() async {
        let session = EngineSessionCoordinatorProbe()
        let graph = PlaybackGraphProbe()
        let engine = NoiseEngine(
            notificationCenter: NotificationCenter(),
            audioSessionCoordinator: session,
            playbackGraphHooks: graph.hooks
        )
        engine.spectrumAnalysisEnabled = false
        var invalidationCount = 0
        var policyAtInvalidation: AudioSessionInactivePolicy?
        engine.onPlaybackRequestInvalidated = {
            invalidationCount += 1
            policyAtInvalidation = session.policies().last
        }
        let staleStart = Task { try await engine.start() }
        #expect(await waitForActivation(session))

        engine._recoverFromMediaServicesReset()

        #expect(invalidationCount == 1)
        #expect(policyAtInvalidation == .systemManaged)
        session.completeNext(.success(()))
        await #expect(throws: CancellationError.self) {
            try await staleStart.value
        }
    }

    @Test func resetRacingBlockedActivationRemainsPausedUntilExplicitStart() async throws {
        let session = EngineSessionCoordinatorProbe()
        let graph = PlaybackGraphProbe()
        let engine = NoiseEngine(
            notificationCenter: NotificationCenter(),
            audioSessionCoordinator: session,
            playbackGraphHooks: graph.hooks
        )
        engine.spectrumAnalysisEnabled = false
        let staleStart = Task { try await engine.start() }
        #expect(await waitForActivation(session))

        engine._recoverFromMediaServicesReset()
        session.completeNext(.success(()))
        await #expect(throws: CancellationError.self) {
            try await staleStart.value
        }
        #expect(!engine.isPlaying)
        #expect(!engine.isPlaybackRequested)

        let explicitStart = Task { try await engine.start() }
        #expect(await waitForActivation(session))
        session.completeNext(.success(()))
        try await explicitStart.value
        #expect(engine.isPlaying)
        #expect(session.policies().contains(.systemManaged))
    }

    @Test func resetClearsDelayedInterruptionResumeAndStaysPaused() async {
        let session = EngineSessionCoordinatorProbe()
        let graph = PlaybackGraphProbe()
        let engine = NoiseEngine(
            notificationCenter: NotificationCenter(),
            audioSessionCoordinator: session,
            playbackGraphHooks: graph.hooks
        )
        engine.spectrumAnalysisEnabled = false
        engine._setPlayingForTesting(true)
        await engine._applyInterruption(type: .began, options: [])

        engine._recoverFromMediaServicesReset()
        await engine._applyInterruption(type: .ended, options: .shouldResume)

        #expect(!engine.isPlaying)
        #expect(!engine.isPlaybackRequested)
        #expect(session.activationCount() == 0)
        #expect(session.policies().last == .systemManaged)
    }

    @Test func rebuildPreservesGainsGlobalAndBandCount() {
        let engine = NoiseEngine()
        engine.setGain(band: 2, dB: 5)
        engine.setGlobalGain(3)
        engine._recoverFromMediaServicesReset()
        #expect(engine.bandCount == 8)
        #expect(engine.gain(band: 2) == 5)
        #expect(abs(engine.globalGain - 3) < 0.001)
        #expect(!engine.isPlaying)
    }

    @Test func rebuildInvalidatesAnalyzerAndUsesRebuiltFormat() {
        let spy = SpectrumAnalyzerFactorySpy()
        let engine = NoiseEngine(
            analyzerFactory: spy.factory,
            notificationCenter: NotificationCenter()
        )
        engine._setPlayingForTesting(true)
        engine._installSpectrumTap()
        let firstGeneration = engine._spectrumGeneration
        engine._setPlayingForTesting(false)

        engine._recoverFromMediaServicesReset()
        #expect(!engine.isSpectrumTapInstalled)
        #expect(spy.lifetimeProbes[0].snapshot().shutdownCount == 1)
        #expect(spy.lifetimeProbes[0].snapshot().deinitCount == 1)

        engine._setPlayingForTesting(true)
        engine._installSpectrumTap()
        #expect(engine._spectrumGeneration > firstGeneration)
        #expect(spy.sampleRates == [44_100, 44_100])
        engine._removeSpectrumTap()
    }

    @Test func invalidGraphRecoveryUsesShadowsAndJoinsBeforeReplacement() {
        let recorder = SpectrumLifecycleRecorder()
        let graphProbe = InvalidGraphLifecycleProbe(recorder: recorder)
        let spy = SpectrumAnalyzerFactorySpy()
        spy.lifecycleRecorder = recorder
        let engine = NoiseEngine(
            analyzerFactory: spy.factory,
            notificationCenter: NotificationCenter(),
            graphLifecycleHooks: graphProbe.hooks
        )
        engine.setGain(band: 2, dB: 5)
        engine.setGlobalGain(3)
        engine._setPlayingForTesting(true)
        engine._installSpectrumTap()
        let installedGeneration = engine._spectrumGeneration
        let lifetimeProbe = spy.lifetimeProbes[0]
        lifetimeProbe.inspectShutdown { [weak engine] in
            MainActor.assumeIsolated {
                SpectrumShutdownObservation(
                    tapInstalled: engine?.isSpectrumTapInstalled,
                    generation: engine?._spectrumGeneration
                )
            }
        }
        engine._setPlayingForTesting(false)
        graphProbe.markGraphLost()

        engine._recoverFromMediaServicesReset()

        let lifetime = lifetimeProbe.snapshot()
        #expect(graphProbe.invalidEQAccessCount == 0)
        #expect(engine.gain(band: 2) == 5)
        #expect(abs(engine.globalGain - 3) < 0.001)
        #expect(!engine.isSpectrumTapInstalled)
        #expect(lifetime.tapInstalledAtShutdown == false)
        #expect(lifetime.generationAtShutdown! > installedGeneration)
        #expect(lifetime.shutdownCount == 1)
        #expect(lifetime.deinitCount == 1)
        #expect(spy.analyzer(at: 0) == nil)
        #expect(
            recorder.snapshot()
                == [
                    .analyzerShutdown,
                    .analyzerDeinit,
                    .graphWillReplace,
                    .graphDidReplace,
                ]
        )
    }

    @Test func resetNotificationRetainsEngineThroughLastExternalRelease() async {
        let recorder = SpectrumLifecycleRecorder()
        let graphProbe = InvalidGraphLifecycleProbe(recorder: recorder)
        let spy = SpectrumAnalyzerFactorySpy()
        spy.lifecycleRecorder = recorder
        let center = NotificationCenter()
        var engine: NoiseEngine? = NoiseEngine(
            analyzerFactory: spy.factory,
            notificationCenter: center,
            graphLifecycleHooks: graphProbe.hooks
        )
        engine?._setPlayingForTesting(true)
        engine?._installSpectrumTap()
        engine?._setPlayingForTesting(false)
        weak let releasedEngine = engine
        let lifetimeProbe = spy.lifetimeProbes[0]
        graphProbe.markGraphLost()

        center.post(
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: nil
        )
        engine = nil
        await lifetimeProbe.waitForDeinit()

        #expect(graphProbe.invalidEQAccessCount == 0)
        #expect(releasedEngine == nil)
        #expect(
            recorder.snapshot()
                == [
                    .analyzerShutdown,
                    .analyzerDeinit,
                    .graphWillReplace,
                    .graphDidReplace,
                ]
        )
    }

    @Test func resetNotificationHopsToMainActor() async {
        let center = NotificationCenter()
        let engine = NoiseEngine(notificationCenter: center)
        engine.isFading = true

        await Task.detached {
            center.post(
                name: AVAudioSession.mediaServicesWereResetNotification,
                object: nil
            )
        }.value
        for _ in 0..<20 where engine.isFading { await Task.yield() }
        #expect(!engine.isFading)
    }
}
