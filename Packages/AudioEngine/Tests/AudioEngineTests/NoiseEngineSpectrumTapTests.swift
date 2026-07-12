import AVFoundation
import Foundation
import RealtimeAtomics
import Testing
@testable import AudioEngine

enum SpectrumLifecycleEvent: Equatable, Sendable {
    case analyzerShutdown
    case analyzerDeinit
    case graphWillReplace
    case graphDidReplace
}

final class SpectrumLifecycleRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [SpectrumLifecycleEvent] = []

    func record(_ event: SpectrumLifecycleEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func snapshot() -> [SpectrumLifecycleEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}

struct SpectrumShutdownObservation: Sendable {
    let tapInstalled: Bool?
    let generation: UInt64?
}

struct SpectrumAnalyzerLifetimeSnapshot: Sendable {
    let shutdownCount: Int
    let deinitCount: Int
    let shutdownOnMainThread: Bool?
    let deinitOnMainThread: Bool?
    let tapInstalledAtShutdown: Bool?
    let generationAtShutdown: UInt64?
}

final class SpectrumAnalyzerLifetimeProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let recorder: SpectrumLifecycleRecorder?
    private let deinitStream: AsyncStream<Void>
    private let deinitContinuation: AsyncStream<Void>.Continuation
    private var shutdownObservation:
        (@Sendable () -> SpectrumShutdownObservation)?
    private var shutdownCount = 0
    private var deinitCount = 0
    private var shutdownOnMainThread: Bool?
    private var deinitOnMainThread: Bool?
    private var tapInstalledAtShutdown: Bool?
    private var generationAtShutdown: UInt64?

    init(recorder: SpectrumLifecycleRecorder?) {
        let deinitSignal = AsyncStream<Void>.makeStream()
        self.recorder = recorder
        deinitStream = deinitSignal.stream
        deinitContinuation = deinitSignal.continuation
    }

    func inspectShutdown(
        using observation: @escaping @Sendable () -> SpectrumShutdownObservation
    ) {
        lock.lock()
        shutdownObservation = observation
        lock.unlock()
    }

    func recordShutdown() {
        lock.lock()
        let observation = shutdownObservation
        lock.unlock()
        let state = observation?()

        lock.lock()
        shutdownCount += 1
        shutdownOnMainThread = Thread.isMainThread
        tapInstalledAtShutdown = state?.tapInstalled
        generationAtShutdown = state?.generation
        lock.unlock()
        recorder?.record(.analyzerShutdown)
    }

    func recordDeinit() {
        lock.lock()
        deinitCount += 1
        deinitOnMainThread = Thread.isMainThread
        lock.unlock()
        recorder?.record(.analyzerDeinit)
        deinitContinuation.yield()
        deinitContinuation.finish()
    }

    func waitForDeinit() async {
        for await _ in deinitStream { return }
    }

    func snapshot() -> SpectrumAnalyzerLifetimeSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return SpectrumAnalyzerLifetimeSnapshot(
            shutdownCount: shutdownCount,
            deinitCount: deinitCount,
            shutdownOnMainThread: shutdownOnMainThread,
            deinitOnMainThread: deinitOnMainThread,
            tapInstalledAtShutdown: tapInstalledAtShutdown,
            generationAtShutdown: generationAtShutdown
        )
    }
}

struct SpectrumSubmissionOwnerLifetimeSnapshot: Sendable {
    let deinitCount: Int
}

final class SpectrumSubmissionOwnerLifetimeProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let deinitStream: AsyncStream<Void>
    private let deinitContinuation: AsyncStream<Void>.Continuation
    private var deinitCount = 0

    init() {
        let deinitSignal = AsyncStream<Void>.makeStream()
        deinitStream = deinitSignal.stream
        deinitContinuation = deinitSignal.continuation
    }

    func recordDeinit() {
        lock.lock()
        deinitCount += 1
        lock.unlock()
        deinitContinuation.yield()
        deinitContinuation.finish()
    }

    func waitForDeinit() async {
        for await _ in deinitStream { return }
    }

    func snapshot() -> SpectrumSubmissionOwnerLifetimeSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return SpectrumSubmissionOwnerLifetimeSnapshot(
            deinitCount: deinitCount
        )
    }
}

final class StubSpectrumSubmissionOwner {
    private let mailbox: SpectrumMailbox
    private let lifetimeProbe: SpectrumSubmissionOwnerLifetimeProbe
    private var claimedFrames: [ClaimedSpectrumFrame] = []

    var context: UnsafeMutableRawPointer { mailbox.opaqueContext }

    init(
        submitSucceeds: Bool,
        lifetimeProbe: SpectrumSubmissionOwnerLifetimeProbe
    ) {
        self.lifetimeProbe = lifetimeProbe
        mailbox = SpectrumMailbox()!

        if !submitSucceeds {
            let values = [Float](
                repeating: 0,
                count: SpectrumMailbox.sampleCount
            )
            for _ in 0..<2 {
                values.withUnsafeBufferPointer { buffer in
                    _ = SpectrumMailbox.submit(
                        context: mailbox.opaqueContext,
                        samples: buffer.baseAddress!,
                        count: buffer.count
                    )
                }
                claimedFrames.append(mailbox.claimLatest()!)
            }
        }
    }

    deinit {
        for frame in claimedFrames {
            mailbox.release(frame)
        }
        lifetimeProbe.recordDeinit()
    }
}

final class StubSpectrumAnalyzer: SpectrumAnalyzing, @unchecked Sendable {
    let submission: SpectrumSubmission
    private let lifetimeProbe: SpectrumAnalyzerLifetimeProbe

    init(
        submitSucceeds: Bool,
        lifetimeProbe: SpectrumAnalyzerLifetimeProbe,
        submissionOwnerLifetimeProbe: SpectrumSubmissionOwnerLifetimeProbe
    ) {
        self.lifetimeProbe = lifetimeProbe
        let owner = StubSpectrumSubmissionOwner(
            submitSucceeds: submitSucceeds,
            lifetimeProbe: submissionOwnerLifetimeProbe
        )
        submission = SpectrumSubmission(
            owner: owner,
            context: owner.context
        )
    }

    deinit {
        lifetimeProbe.recordDeinit()
    }

    func shutdown() {
        lifetimeProbe.recordShutdown()
    }
}

private final class WeakSpectrumAnalyzerReference {
    weak var value: StubSpectrumAnalyzer?

    init(_ value: StubSpectrumAnalyzer) {
        self.value = value
    }
}

private final class NoiseEngineReleaseBox: @unchecked Sendable {
    private var engine: NoiseEngine?

    init(_ engine: NoiseEngine?) {
        self.engine = engine
    }

    func release() {
        engine = nil
    }
}

@MainActor
final class SpectrumAnalyzerFactorySpy {
    var setupFails = false
    var submitSucceeds = true
    var lifecycleRecorder: SpectrumLifecycleRecorder?
    private(set) var sampleRates: [Double] = []
    private(set) var generations: [UInt64] = []
    private var analyzerReferences: [WeakSpectrumAnalyzerReference] = []
    private(set) var lifetimeProbes: [SpectrumAnalyzerLifetimeProbe] = []
    private(set) var submissionOwnerLifetimeProbes: [
        SpectrumSubmissionOwnerLifetimeProbe
    ] = []
    private(set) var deliveries: [
        @Sendable (SpectrumSnapshot, UInt64) -> Void
    ] = []

    var createdAnalyzerCount: Int { analyzerReferences.count }

    var factory: SpectrumAnalyzerFactory {
        { [weak self] sampleRate, generation, deliver in
            guard let self else { return nil }
            sampleRates.append(sampleRate)
            generations.append(generation)
            guard !setupFails else { return nil }

            let lifetimeProbe = SpectrumAnalyzerLifetimeProbe(
                recorder: lifecycleRecorder
            )
            let submissionOwnerLifetimeProbe =
                SpectrumSubmissionOwnerLifetimeProbe()
            let analyzer = StubSpectrumAnalyzer(
                submitSucceeds: submitSucceeds,
                lifetimeProbe: lifetimeProbe,
                submissionOwnerLifetimeProbe: submissionOwnerLifetimeProbe
            )
            analyzerReferences.append(
                WeakSpectrumAnalyzerReference(analyzer)
            )
            lifetimeProbes.append(lifetimeProbe)
            submissionOwnerLifetimeProbes.append(
                submissionOwnerLifetimeProbe
            )
            deliveries.append(deliver)
            return analyzer
        }
    }

    func analyzer(at index: Int) -> StubSpectrumAnalyzer? {
        analyzerReferences[index].value
    }

    func complete(
        _ snapshot: SpectrumSnapshot,
        deliveryIndex: Int
    ) {
        deliveries[deliveryIndex](
            snapshot,
            generations[deliveryIndex]
        )
    }
}

@MainActor
@Suite("NoiseEngine spectrum tap")
struct NoiseEngineSpectrumTapTests {
    @Test func installAndRemoveAreIdempotent() {
        let recorder = SpectrumLifecycleRecorder()
        let spy = SpectrumAnalyzerFactorySpy()
        spy.lifecycleRecorder = recorder
        let engine = makeEngine(spy)
        engine._setPlayingForTesting(true)

        engine._installSpectrumTap()
        #expect(engine.isSpectrumTapInstalled)
        #expect(spy.createdAnalyzerCount == 1)

        engine._installSpectrumTap()
        #expect(spy.createdAnalyzerCount == 1)

        engine._removeSpectrumTap()
        #expect(!engine.isSpectrumTapInstalled)
        #expect(spy.lifetimeProbes[0].snapshot().shutdownCount == 1)
        #expect(spy.lifetimeProbes[0].snapshot().deinitCount == 1)

        engine._removeSpectrumTap()
        #expect(spy.lifetimeProbes[0].snapshot().shutdownCount == 1)
        #expect(
            recorder.snapshot()
                == [.analyzerShutdown, .analyzerDeinit]
        )
    }

    @Test func enablementRespectsPlaybackState() {
        let stoppedSpy = SpectrumAnalyzerFactorySpy()
        let stopped = makeEngine(stoppedSpy)
        stopped.spectrumAnalysisEnabled = false
        stopped.spectrumAnalysisEnabled = true
        #expect(!stopped.isSpectrumTapInstalled)
        #expect(stoppedSpy.createdAnalyzerCount == 0)

        let playingSpy = SpectrumAnalyzerFactorySpy()
        let playing = makeEngine(playingSpy)
        playing._setPlayingForTesting(true)
        playing._installSpectrumTap()
        playing.spectrumAnalysisEnabled = false
        #expect(!playing.isSpectrumTapInstalled)
        #expect(
            playingSpy.lifetimeProbes[0].snapshot().shutdownCount == 1
        )
    }

    @Test func stoppingRemovesTapAndJoinsAnalyzer() {
        let spy = SpectrumAnalyzerFactorySpy()
        let engine = makeEngine(spy)
        engine._setPlayingForTesting(true)
        engine._installSpectrumTap()

        engine.stop()

        #expect(!engine.isPlaying)
        #expect(!engine.isSpectrumTapInstalled)
        #expect(spy.lifetimeProbes[0].snapshot().shutdownCount == 1)
    }

    @Test func removalInvalidatesGenerationBeforeShutdownAndDestruction() {
        let recorder = SpectrumLifecycleRecorder()
        let spy = SpectrumAnalyzerFactorySpy()
        spy.lifecycleRecorder = recorder
        let engine = makeEngine(spy)
        engine._setPlayingForTesting(true)
        engine._installSpectrumTap()
        let installedGeneration = engine._spectrumGeneration

        #expect(spy.analyzer(at: 0) != nil)
        let lifetimeProbe = spy.lifetimeProbes[0]
        lifetimeProbe.inspectShutdown { [weak engine] in
            MainActor.assumeIsolated {
                SpectrumShutdownObservation(
                    tapInstalled: engine?.isSpectrumTapInstalled,
                    generation: engine?._spectrumGeneration
                )
            }
        }
        engine._removeSpectrumTap()

        let snapshot = lifetimeProbe.snapshot()
        #expect(snapshot.tapInstalledAtShutdown == false)
        #expect(snapshot.generationAtShutdown! > installedGeneration)
        #expect(snapshot.shutdownCount == 1)
        #expect(snapshot.deinitCount == 1)
        #expect(spy.analyzer(at: 0) == nil)
        #expect(
            recorder.snapshot()
                == [.analyzerShutdown, .analyzerDeinit]
        )
    }

    @Test func mediaResetShutsDownAnalyzerBeforeDeinit() {
        let recorder = SpectrumLifecycleRecorder()
        let spy = SpectrumAnalyzerFactorySpy()
        spy.lifecycleRecorder = recorder
        let engine = makeEngine(spy)
        engine._setPlayingForTesting(true)
        engine._installSpectrumTap()
        engine._setPlayingForTesting(false)

        engine._recoverFromMediaServicesReset()

        #expect(
            recorder.snapshot()
                == [.analyzerShutdown, .analyzerDeinit]
        )
    }

    @Test func detachedLastReleaseRunsTeardownOnMainActor() async throws {
        let recorder = SpectrumLifecycleRecorder()
        let spy = SpectrumAnalyzerFactorySpy()
        spy.lifecycleRecorder = recorder
        var engine: NoiseEngine? = makeEngine(spy)
        engine?._setPlayingForTesting(true)
        engine?._installSpectrumTap()
        let lifetimeProbe = spy.lifetimeProbes[0]
        #expect(spy.analyzer(at: 0) != nil)
        let releaseBox = NoiseEngineReleaseBox(engine)
        engine = nil

        await Task.detached {
            releaseBox.release()
        }.value
        await lifetimeProbe.waitForDeinit()

        let snapshot = lifetimeProbe.snapshot()
        #expect(snapshot.shutdownCount == 1)
        #expect(snapshot.deinitCount == 1)
        #expect(snapshot.shutdownOnMainThread == true)
        #expect(snapshot.deinitOnMainThread == true)
        #expect(spy.analyzer(at: 0) == nil)
        #expect(
            recorder.snapshot()
                == [.analyzerShutdown, .analyzerDeinit]
        )
    }

    @Test func setupAndSubmissionFailuresAreNonFatal() throws {
        let setupSpy = SpectrumAnalyzerFactorySpy()
        setupSpy.setupFails = true
        let setupEngine = makeEngine(setupSpy)
        setupEngine._setPlayingForTesting(true)
        setupEngine.setGain(band: 2, dB: 5)
        setupEngine.masterVolume = 0.4
        var setupPlaybackChanges = 0
        setupEngine.onPlaybackStateChange = { _ in
            setupPlaybackChanges += 1
        }
        setupEngine._installSpectrumTap()
        #expect(setupEngine.isPlaying)
        #expect(!setupEngine.isSpectrumTapInstalled)
        #expect(setupEngine.bandCount == 8)
        #expect(setupEngine.gain(band: 2) == 5)
        #expect(setupEngine.masterVolume == 0.4)
        #expect(setupPlaybackChanges == 0)

        let submitSpy = SpectrumAnalyzerFactorySpy()
        submitSpy.submitSucceeds = false
        let submitEngine = makeEngine(submitSpy)
        submitEngine._setPlayingForTesting(true)
        var submitPlaybackChanges = 0
        var submitSpectrumChanges = 0
        submitEngine.onPlaybackStateChange = { _ in
            submitPlaybackChanges += 1
        }
        submitEngine.onSpectrumSnapshot = { _, _ in
            submitSpectrumChanges += 1
        }
        submitEngine._installSpectrumTap()
        let analyzer = try #require(submitSpy.analyzer(at: 0))
        let samples = [Float](repeating: 0, count: SpectrumFFT.sampleCount)
        let accepted = samples.withUnsafeBufferPointer { buffer in
            analyzer.submission.submit(
                buffer.baseAddress!,
                count: buffer.count
            )
        }
        #expect(!accepted)
        #expect(submitEngine.isPlaying)
        #expect(submitEngine.isSpectrumTapInstalled)
        #expect(submitEngine.bandCount == 8)
        #expect(submitPlaybackChanges == 0)
        #expect(submitSpectrumChanges == 0)
        submitEngine._removeSpectrumTap()
    }

    @Test func deliveryRequiresCurrentActiveGeneration() async {
        let spy = SpectrumAnalyzerFactorySpy()
        let engine = makeEngine(spy)
        var received: [SpectrumSnapshot] = []
        engine.onSpectrumSnapshot = { snapshot, _ in received.append(snapshot) }
        engine._setPlayingForTesting(true)
        engine._installSpectrumTap()

        let first = SpectrumSnapshot(
            bands: SIMD8<Float>(repeating: 0.5),
            rms: 0.4,
            peak: 0.3
        )
        spy.complete(first, deliveryIndex: 0)
        for _ in 0..<20 where received.isEmpty { await Task.yield() }
        #expect(received == [first])

        engine._removeSpectrumTap()
        spy.complete(.zero, deliveryIndex: 0)
        for _ in 0..<20 { await Task.yield() }
        #expect(received == [first])
    }

    @Test func deliveryWhileStoppedOrDisabledIsDiscarded() async {
        let spy = SpectrumAnalyzerFactorySpy()
        let engine = makeEngine(spy)
        var deliveryCount = 0
        engine.onSpectrumSnapshot = { _, _ in deliveryCount += 1 }
        engine._setPlayingForTesting(true)
        engine._installSpectrumTap()

        engine._setPlayingForTesting(false)
        spy.complete(.zero, deliveryIndex: 0)
        for _ in 0..<10 { await Task.yield() }
        #expect(deliveryCount == 0)

        engine._setPlayingForTesting(true)
        engine.spectrumAnalysisEnabled = false
        spy.complete(.zero, deliveryIndex: 0)
        for _ in 0..<10 { await Task.yield() }
        #expect(deliveryCount == 0)
    }

    @Test func reinstallUsesIncreasingGenerationAndEQSampleRate() {
        let spy = SpectrumAnalyzerFactorySpy()
        let engine = makeEngine(spy)
        engine._setPlayingForTesting(true)
        engine._installSpectrumTap()
        let firstGeneration = engine._spectrumGeneration
        engine._removeSpectrumTap()
        engine._installSpectrumTap()

        #expect(engine._spectrumGeneration > firstGeneration)
        #expect(spy.sampleRates == [44_100, 44_100])
        engine._removeSpectrumTap()
    }

    @Test func blockedMainDeliveryKeepsOnlyNewestAnalyzerCompletion() {
        let scheduler = SpectrumMainJobRecorder()
        let spy = SpectrumAnalyzerFactorySpy()
        let engine = makeEngine(spy, schedule: scheduler.schedule)
        var received: [SpectrumSnapshot] = []
        engine.onSpectrumSnapshot = { snapshot, _ in received.append(snapshot) }
        engine._setPlayingForTesting(true)
        engine._installSpectrumTap()

        for index in 0..<128 {
            spy.complete(
                SpectrumSnapshot(
                    bands: SIMD8<Float>(repeating: Float(index) / 127),
                    rms: Float(index) / 127,
                    peak: Float(index) / 127
                ),
                deliveryIndex: 0
            )
        }

        #expect(scheduler.totalScheduled == 1)
        scheduler.runNext()
        #expect(received.count == 1)
        #expect(received[0].rms == 1)
        engine._removeSpectrumTap()
    }

    @Test func staleReinstallCompletionCannotDisplaceCurrentPending() {
        let scheduler = SpectrumMainJobRecorder()
        let spy = SpectrumAnalyzerFactorySpy()
        let engine = makeEngine(spy, schedule: scheduler.schedule)
        var received: [SpectrumSnapshot] = []
        engine.onSpectrumSnapshot = { snapshot, _ in received.append(snapshot) }
        engine._setPlayingForTesting(true)
        engine._installSpectrumTap()
        spy.complete(.zero, deliveryIndex: 0)

        engine._removeSpectrumTap()
        engine._installSpectrumTap()
        let current = SpectrumSnapshot(
            bands: SIMD8<Float>(repeating: 0.75),
            rms: 0.75,
            peak: 0.75
        )
        spy.complete(current, deliveryIndex: 1)
        spy.complete(
            SpectrumSnapshot(
                bands: SIMD8<Float>(repeating: 1),
                rms: 1,
                peak: 1
            ),
            deliveryIndex: 0
        )

        #expect(scheduler.totalScheduled == 1)
        scheduler.runNext()
        #expect(received == [current])
        engine._removeSpectrumTap()
    }

    @Test func tapBlockOwnsSubmissionStorageUntilNodeRelease() async {
        let ownerProbe = SpectrumSubmissionOwnerLifetimeProbe()
        var owner: StubSpectrumSubmissionOwner? =
            StubSpectrumSubmissionOwner(
                submitSucceeds: true,
                lifetimeProbe: ownerProbe
            )
        var submission: SpectrumSubmission? = SpectrumSubmission(
            owner: owner!,
            context: owner!.context
        )
        var audioEngine: AVAudioEngine? = AVAudioEngine()
        var node: AVAudioUnitEQ? = AVAudioUnitEQ(numberOfBands: 1)
        let format = AVAudioFormat(
            standardFormatWithSampleRate: 44_100,
            channels: 2
        )!
        audioEngine!.attach(node!)
        audioEngine!.connect(
            node!,
            to: audioEngine!.mainMixerNode,
            format: format
        )

        rt_audio_node_install_spectrum_tap(
            Unmanaged.passUnretained(node!).toOpaque(),
            0,
            AVAudioFrameCount(SpectrumFFT.sampleCount),
            submission!.context,
            Unmanaged.passRetained(submission!.owner).toOpaque(),
            { context in
                Unmanaged<AnyObject>.fromOpaque(context).release()
            }
        )
        submission = nil
        owner = nil

        #expect(ownerProbe.snapshot().deinitCount == 0)

        node!.removeTap(onBus: 0)
        audioEngine!.detach(node!)
        node = nil
        audioEngine = nil
        await ownerProbe.waitForDeinit()

        #expect(ownerProbe.snapshot().deinitCount == 1)
    }

    private func makeEngine(
        _ spy: SpectrumAnalyzerFactorySpy,
        schedule: @escaping SpectrumDeliveryGate.Scheduler =
            SpectrumDeliveryGate.defaultSchedule
    ) -> NoiseEngine {
        NoiseEngine(
            analyzerFactory: spy.factory,
            notificationCenter: NotificationCenter(),
            spectrumDeliverySchedule: schedule
        )
    }
}
