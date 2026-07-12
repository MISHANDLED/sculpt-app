import Testing
@testable import Sculptor
@testable import AudioEngine
import Combine
import Foundation
import MediaPlayer

private enum PlaybackStartTestError: Error {
    case failed
}

private final class PlaybackSessionProbe: AudioSessionCoordinating,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<Void, Error>] = []
    private var activationCalls = 0
    private var policies: [AudioSessionInactivePolicy] = []
    let activationEntered = DispatchSemaphore(value: 0)

    func activate() async throws {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                activationCalls += 1
                waiters.append(continuation)
            }
            activationEntered.signal()
        }
    }

    func requestInactive(_ policy: AudioSessionInactivePolicy) {
        lock.withLock { policies.append(policy) }
    }

    func waitUntilIdle() async {}

    func completeNext(_ result: Result<Void, Error>) {
        let continuation = lock.withLock { waiters.removeFirst() }
        continuation.resume(with: result)
    }

    func activationCount() -> Int {
        lock.withLock { activationCalls }
    }
}

@MainActor
private final class PlaybackViewModelGraphProbe: @unchecked Sendable {
    var running = false
    var startCount = 0

    var hooks: NoiseEnginePlaybackGraphHooks {
        NoiseEnginePlaybackGraphHooks(
            isRunning: { [weak self] _ in self?.running == true },
            start: { [weak self] _ in
                self?.startCount += 1
                self?.running = true
            },
            stop: { [weak self] _ in self?.running = false }
        )
    }
}

private func waitForPlaybackActivation(
    _ probe: PlaybackSessionProbe
) async -> Bool {
    await withCheckedContinuation { continuation in
        DispatchQueue.global().async {
            continuation.resume(
                returning: probe.activationEntered.wait(
                    timeout: .now() + 2
                ) == .success
            )
        }
    }
}

@MainActor
@Suite struct PlaybackViewModelTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "test-\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    private func makePendingStartViewModel() -> (
        PlaybackViewModel,
        NoiseEngine,
        PlaybackSessionProbe,
        PlaybackViewModelGraphProbe
    ) {
        let session = PlaybackSessionProbe()
        let graph = PlaybackViewModelGraphProbe()
        let engine = NoiseEngine(
            notificationCenter: NotificationCenter(),
            audioSessionCoordinator: session,
            playbackGraphHooks: graph.hooks
        )
        let viewModel = PlaybackViewModel(
            engine: engine,
            defaults: freshDefaults()
        )
        return (viewModel, engine, session, graph)
    }

    @Test func canceledBeforeFirstExecutionNeverRegistersActiveIntent() async {
        let (vm, engine, session, _) = makePendingStartViewModel()

        vm.togglePlay()
        vm.togglePlay()
        for _ in 0..<10 { await Task.yield() }

        #expect(session.activationCount() == 0)
        #expect(!engine.isPlaybackRequested)
        #expect(!vm.isPlaying)
        #expect(vm.errorText == nil)
    }

    @Test func secondToggleWhileStartingCancelsWithoutError() async {
        let (vm, engine, session, _) = makePendingStartViewModel()
        vm.togglePlay()
        #expect(await waitForPlaybackActivation(session))

        vm.togglePlay()
        session.completeNext(.success(()))
        for _ in 0..<10 { await Task.yield() }

        #expect(!engine.isPlaybackRequested)
        #expect(!vm.isPlaying)
        #expect(vm.errorText == nil)
    }

    @Test func remotePauseWhileStartingCancelsWithoutError() async {
        let (vm, engine, session, _) = makePendingStartViewModel()
        vm.togglePlay()
        #expect(await waitForPlaybackActivation(session))

        vm._handleRemotePause()
        session.completeNext(.success(()))
        for _ in 0..<10 { await Task.yield() }

        #expect(!engine.isPlaybackRequested)
        #expect(!vm.isPlaying)
        #expect(vm.errorText == nil)
    }

    @Test func sleepExpiryWhileStartingCancelsWithoutError() async {
        let (vm, engine, session, _) = makePendingStartViewModel()
        vm.togglePlay()
        #expect(await waitForPlaybackActivation(session))
        vm.startSleepTimer(minutes: 1)

        vm._sleepTick(now: Date().addingTimeInterval(61))
        session.completeNext(.success(()))
        for _ in 0..<10 { await Task.yield() }

        #expect(!engine.isPlaybackRequested)
        #expect(!vm.isPlaying)
        #expect(vm.errorText == nil)
        #expect(vm.sleepMinutes == nil)
    }

    @Test func staleStartFailureCannotOverwriteNewerState() async {
        let (vm, _, session, graph) = makePendingStartViewModel()
        vm.togglePlay()
        #expect(await waitForPlaybackActivation(session))
        vm.togglePlay()
        vm.togglePlay()
        #expect(await waitForPlaybackActivation(session))

        session.completeNext(.failure(PlaybackStartTestError.failed))
        session.completeNext(.success(()))
        for _ in 0..<20 where !vm.isPlaying { await Task.yield() }

        #expect(vm.isPlaying)
        #expect(vm.errorText == nil)
        #expect(graph.startCount == 1)
    }

    @Test func currentActivationFailurePublishesErrorAndStaysStopped() async {
        let (vm, engine, session, _) = makePendingStartViewModel()
        vm.togglePlay()
        #expect(await waitForPlaybackActivation(session))

        session.completeNext(.failure(PlaybackStartTestError.failed))
        for _ in 0..<20 where vm.errorText == nil { await Task.yield() }

        #expect(!engine.isPlaybackRequested)
        #expect(!vm.isPlaying)
        #expect(vm.errorText != nil)
    }

    @Test func selectPresetSetsBuiltinSelection() {
        let vm = PlaybackViewModel(defaults: freshDefaults())
        vm.select(.pink)
        #expect(vm.gains == NoisePreset.pink.gains)
        #expect(vm.selection == .builtin(.pink))
    }

    @Test func applyCustomSetsCustomSelectionAndGains() {
        let vm = PlaybackViewModel(defaults: freshDefaults())
        let id = UUID()
        let g: [Float] = [3, 2, 1, 0, -1, -2, -3, -4]
        vm.applyCustom(id: id, gains: g)
        #expect(vm.gains == g)
        #expect(vm.selection == .custom(id))
    }

    // UPDATED: setGain now sets isEdited=true and PRESERVES selection
    @Test func draggingABandSetsIsEditedAndPreservesSelection() {
        let vm = PlaybackViewModel(defaults: freshDefaults())
        vm.select(.pink)
        vm.setGain(band: 0, dB: 5)
        #expect(vm.selection == .builtin(.pink))   // preserved
        #expect(vm.isEdited == true)
        #expect(vm.gains[0] == 5)
    }

    @Test func selectClearsIsEdited() {
        let vm = PlaybackViewModel(defaults: freshDefaults())
        vm.setGain(band: 0, dB: 5)
        vm.select(.pink)
        #expect(vm.isEdited == false)
        #expect(vm.selection == .builtin(.pink))
    }

    @Test func applyCustomClearsIsEdited() {
        let vm = PlaybackViewModel(defaults: freshDefaults())
        vm.setGain(band: 0, dB: 5)
        let id = UUID()
        vm.applyCustom(id: id, gains: [Float](repeating: 0, count: 8))
        #expect(vm.isEdited == false)
        #expect(vm.selection == .custom(id))
    }

    @Test func resetZerosGainsAndClearsState() {
        let vm = PlaybackViewModel(defaults: freshDefaults())
        vm.select(.pink)
        vm.setGain(band: 0, dB: 5)
        vm.reset()
        #expect(vm.gains.allSatisfy { $0 == 0 })
        #expect(vm.selection == .none)
        #expect(vm.isEdited == false)
    }

    @Test func builtinDisplayName() {
        let vm = PlaybackViewModel(defaults: freshDefaults())
        vm.select(.pink)
        #expect(vm.presetDisplayName == "Pink")
        vm.select(.white)
        #expect(vm.presetDisplayName == "White")
        vm.select(.brown)
        #expect(vm.presetDisplayName == "Brown")
        vm.select(.grey)
        #expect(vm.presetDisplayName == "Grey")
        vm.select(.speechBlocker)
        #expect(vm.presetDisplayName == "Speech blocker")
    }

    @Test func noneDisplayName() {
        let vm = PlaybackViewModel(defaults: freshDefaults())
        #expect(vm.presetDisplayName == "Custom")
    }

    @Test func presetToRenameSetAndClear() {
        let vm = PlaybackViewModel(defaults: freshDefaults())
        #expect(vm.presetToRename == nil)
        let id = UUID()
        vm.presetToRename = id
        #expect(vm.presetToRename == id)
        vm.presetToRename = nil
        #expect(vm.presetToRename == nil)
    }

    @Test func spectrumCallbackIsIgnoredWhilePaused() {
        let engine = NoiseEngine()
        let vm = PlaybackViewModel(engine: engine, defaults: freshDefaults())
        let snapshot = SpectrumSnapshot(
            bands: SIMD8<Float>(repeating: 0.5),
            rms: 0.5,
            peak: 0.5
        )

        vm.setVisualizationActive(true)
        engine.onSpectrumSnapshot?(snapshot, ContinuousClock().now)

        #expect(vm.spectrumSnapshot == .zero)
        #expect(vm.spectrumReceivedAt == nil)
    }

    @Test func spectrumCallbackIsAcceptedWhilePlayingAndVisible() {
        let engine = NoiseEngine()
        let vm = PlaybackViewModel(engine: engine, defaults: freshDefaults())
        let snapshot = SpectrumSnapshot(
            bands: SIMD8<Float>(repeating: 0.5),
            rms: 0.5,
            peak: 0.75
        )

        vm.setVisualizationActive(true)
        engine.onPlaybackStateChange?(true)
        engine.onSpectrumSnapshot?(snapshot, ContinuousClock().now)

        #expect(vm.spectrumSnapshot == snapshot)
        #expect(vm.spectrumReceivedAt != nil)
    }

    @Test func spectrumCallbackIsIgnoredWhileVisualizationInactive() {
        let engine = NoiseEngine()
        let vm = PlaybackViewModel(engine: engine, defaults: freshDefaults())
        let snapshot = SpectrumSnapshot(
            bands: SIMD8<Float>(repeating: 0.8),
            rms: 0.8,
            peak: 0.8
        )

        engine.onPlaybackStateChange?(true)
        engine.onSpectrumSnapshot?(snapshot, ContinuousClock().now)

        #expect(vm.spectrumSnapshot == .zero)
        #expect(vm.spectrumReceivedAt == nil)
    }

    @Test func inactiveVisualizationClearsTargetAndDisablesAnalysis() {
        let engine = NoiseEngine()
        let vm = PlaybackViewModel(engine: engine, defaults: freshDefaults())
        let now = ContinuousClock().now
        let snapshot = SpectrumSnapshot(
            bands: SIMD8<Float>(repeating: 0.8),
            rms: 0.8,
            peak: 0.8
        )

        vm.setVisualizationActive(true)
        vm._applyPlaybackState(true)
        vm._ingestSpectrumSnapshot(snapshot, at: now)
        vm.setVisualizationActive(false)

        #expect(!vm.visualizationActive)
        #expect(vm.spectrumSnapshot == .zero)
        #expect(vm.spectrumReceivedAt == nil)
        #expect(!engine.spectrumAnalysisEnabled)
    }

    @Test func delayedSpectrumCallbackPreservesAnalysisTimeAndIsImmediatelyStale() {
        let engine = NoiseEngine()
        let vm = PlaybackViewModel(engine: engine, defaults: freshDefaults())
        let clock = ContinuousClock()
        let analyzedAt = clock.now
        let deliveredAt = analyzedAt.advanced(by: .milliseconds(500))
        let snapshot = SpectrumSnapshot(
            bands: SIMD8<Float>(repeating: 1),
            rms: 1,
            peak: 1
        )
        vm.setVisualizationActive(true)
        engine.onPlaybackStateChange?(true)

        engine.onSpectrumSnapshot?(snapshot, analyzedAt)

        #expect(vm.spectrumReceivedAt == analyzedAt)
        var ripple = RippleAnimationState(at: deliveredAt)
        ripple.retarget(
            to: RippleAnimationInput(
                snapshot: vm.spectrumSnapshot,
                receivedAt: vm.spectrumReceivedAt,
                isPlaying: vm.isPlaying,
                masterVolume: vm.masterVolume,
                isActive: vm.visualizationActive,
                reduceMotion: false,
                lowPowerMode: false
            ),
            at: deliveredAt
        )
        #expect(ripple.uniforms(at: deliveredAt).rms == 0)
    }

    @Test func activeVisualizationReenablesAnalysis() {
        let engine = NoiseEngine()
        let vm = PlaybackViewModel(engine: engine, defaults: freshDefaults())
        #expect(!engine.spectrumAnalysisEnabled)

        vm.setVisualizationActive(true)

        #expect(vm.visualizationActive)
        #expect(engine.spectrumAnalysisEnabled)
    }

    @Test func playbackStopClearsSpectrumTarget() {
        let vm = PlaybackViewModel(defaults: freshDefaults())
        let now = ContinuousClock().now
        let snapshot = SpectrumSnapshot(
            bands: SIMD8<Float>(repeating: 1),
            rms: 1,
            peak: 1
        )

        vm.setVisualizationActive(true)
        vm._applyPlaybackState(true)
        vm._ingestSpectrumSnapshot(snapshot, at: now)
        vm._applyPlaybackState(false)

        #expect(vm.spectrumSnapshot == .zero)
        #expect(vm.spectrumReceivedAt == nil)
    }

    @Test func repeatedPlaybackStateDoesNotRepublishIsPlaying() {
        let vm = PlaybackViewModel(defaults: freshDefaults())
        var emissions: [Bool] = []
        let cancellable = vm.$isPlaying
            .dropFirst()
            .sink { emissions.append($0) }

        vm._applyPlaybackState(true)
        vm._applyPlaybackState(true)
        vm._applyPlaybackState(false)
        vm._applyPlaybackState(false)

        withExtendedLifetime(cancellable) {
            #expect(emissions == [true, false])
        }
    }

    @Test func missingSpectrumUpdatesPreservePlaybackTimerAndNowPlaying() {
        let engine = NoiseEngine()
        let vm = PlaybackViewModel(engine: engine, defaults: freshDefaults())
        vm.nowPlayingTitle = "Failure fallback"
        vm.setGain(band: 3, dB: 4.5)
        vm.errorText = "Sentinel error"
        vm.setVisualizationActive(true)
        engine.onPlaybackStateChange?(true)
        vm.startSleepTimer(minutes: 30)
        vm._sleepTick(now: Date().addingTimeInterval(1))

        #expect(vm.isPlaying)
        #expect(vm.spectrumSnapshot == .zero)
        #expect(vm.sleepMinutes == 30)
        #expect((vm.sleepRemaining ?? 0) > 29 * 60)
        #expect(vm.gains[3] == 4.5)
        #expect(vm.errorText == "Sentinel error")
        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        #expect(info?[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 1)
        #expect(info?[MPMediaItemPropertyTitle] as? String == "Failure fallback")
        vm.cancelSleepTimer()
    }

    @Test func startSleepTimerSetsMinutesAndRemaining() {
        let vm = PlaybackViewModel(defaults: freshDefaults())
        vm.startSleepTimer(minutes: 30)
        #expect(vm.sleepMinutes == 30)
        let remaining = vm.sleepRemaining ?? 0
        #expect(remaining > 30 * 60 - 1 && remaining <= 30 * 60)
        vm.cancelSleepTimer()   // stop the tick loop
    }

    @Test func cancelSleepTimerClearsState() {
        let vm = PlaybackViewModel(defaults: freshDefaults())
        vm.startSleepTimer(minutes: 15)
        vm.cancelSleepTimer()
        #expect(vm.sleepMinutes == nil)
        #expect(vm.sleepRemaining == nil)
    }

    @Test func sleepTickBeforeDeadlineUpdatesRemaining() {
        let vm = PlaybackViewModel(defaults: freshDefaults())
        vm.startSleepTimer(minutes: 30)
        vm._sleepTick(now: Date().addingTimeInterval(60))  // 1 minute elapsed
        let remaining = vm.sleepRemaining ?? 0
        #expect(remaining > 28 * 60 && remaining < 30 * 60)
        #expect(vm.sleepMinutes == 30)
        vm.cancelSleepTimer()
    }

    @Test func sleepTickPastDeadlineStopsAndClears() {
        let vm = PlaybackViewModel(defaults: freshDefaults())
        vm.startSleepTimer(minutes: 30)
        vm._sleepTick(now: Date().addingTimeInterval(31 * 60))  // past deadline
        #expect(vm.sleepRemaining == nil)
        #expect(vm.sleepMinutes == nil)
        #expect(vm.isPlaying == false)
    }

    @Test func startSleepTimerTwiceReplacesDuration() {
        let vm = PlaybackViewModel(defaults: freshDefaults())
        vm.startSleepTimer(minutes: 15)
        vm.startSleepTimer(minutes: 45)
        #expect(vm.sleepMinutes == 45)
        vm.cancelSleepTimer()
    }

    // MARK: - Restore tests (shared suite simulates relaunch)

    @Test func restoresLastBuiltinSelection() {
        let suite = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let vm1 = PlaybackViewModel(defaults: suite)
        vm1.select(.pink)
        let vm2 = PlaybackViewModel(defaults: suite)
        #expect(vm2.selection == .builtin(.pink))
        #expect(vm2.gains == NoisePreset.pink.gains)
    }

    @Test func restoresLastCustomSelection() {
        let suite = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let vm1 = PlaybackViewModel(defaults: suite)
        let id = UUID()
        let g: [Float] = [3, 2, 1, 0, -1, -2, -3, -4]
        vm1.applyCustom(id: id, gains: g)
        let vm2 = PlaybackViewModel(defaults: suite)
        #expect(vm2.selection == .custom(id))
        #expect(vm2.gains == g)
    }

    @Test func resetClearsPersistedSelection() {
        let suite = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let vm1 = PlaybackViewModel(defaults: suite)
        vm1.select(.pink)
        vm1.reset()
        let vm2 = PlaybackViewModel(defaults: suite)
        #expect(vm2.selection == .none)
        #expect(vm2.gains.allSatisfy { $0 == 0 })
    }

    @Test func freshDefaultsStartAtNone() {
        let vm = PlaybackViewModel(defaults: freshDefaults())
        #expect(vm.selection == .none)
    }

    @Test func masterVolumeDefaultsToFullAndPersists() {
        let d = freshDefaults()
        let vm = PlaybackViewModel(defaults: d)
        #expect(vm.masterVolume == 1.0)
        vm.masterVolume = 0.4
        let vm2 = PlaybackViewModel(defaults: d)
        #expect(abs(vm2.masterVolume - 0.4) < 0.001)
    }

    // MARK: - Makeup gain stays live with edits (Finding 1)

    @Test func setGainRecomputesMakeupFromLiveGainsNotStalePreset() {
        let engine = NoiseEngine()
        let vm = PlaybackViewModel(engine: engine, defaults: freshDefaults())
        vm.select(.brown)
        let staleMakeup = engine.globalGain
        vm.setGain(band: 0, dB: 12)   // sculpt the low band hot
        let expected = NoisePreset.makeupGain(for: vm.gains)
        #expect(abs(engine.globalGain - expected) < 0.01)
        #expect(abs(engine.globalGain - staleMakeup) > 0.01)   // must have moved off the preset's canonical makeup
    }

    @Test func setGainOnCustomPresetKeepsZeroMakeup() {
        let engine = NoiseEngine()
        let vm = PlaybackViewModel(engine: engine, defaults: freshDefaults())
        // Deliberately quiet custom preset — recomputing makeup here would clamp to +12.
        vm.applyCustom(id: UUID(), gains: [Float](repeating: -12, count: 8))
        #expect(engine.globalGain == 0)
        vm.setGain(band: 0, dB: -11.5)   // sub-dB nudge must not jump loudness
        #expect(engine.globalGain == 0)
    }

    @Test func setGainWithNoSelectionKeepsZeroMakeup() {
        let engine = NoiseEngine()
        let vm = PlaybackViewModel(engine: engine, defaults: freshDefaults())
        vm.reset()
        vm.setGain(band: 0, dB: -12)
        #expect(engine.globalGain == 0)
    }

    @Test func restoreLastSelectionComputesMakeupFromStoredGainsNotPreset() {
        let suite = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        suite.set("builtin:brown", forKey: "sculptor.lastSelection")
        let editedGains: [Double] = [12, 0, 0, 0, 0, 0, 0, 0]   // not brown's canonical gains
        suite.set(editedGains, forKey: "sculptor.lastGains")
        let engine = NoiseEngine()
        _ = PlaybackViewModel(engine: engine, defaults: suite)
        let expected = NoisePreset.makeupGain(for: editedGains.map(Float.init))
        #expect(abs(engine.globalGain - expected) < 0.01)
        #expect(abs(engine.globalGain - NoisePreset.brown.makeupGain) > 0.01)
    }

    @Test func nowPlayingTitlePublishesToInfoCenter() {
        let vm = PlaybackViewModel(defaults: freshDefaults())
        vm.nowPlayingTitle = "Rain Machine"
        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        #expect(info?[MPMediaItemPropertyTitle] as? String == "Rain Machine")
        #expect(info?[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 0)
    }
}
