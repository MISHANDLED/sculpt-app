import Foundation
import Testing
@testable import AudioEngine

final class StubSpectrumAnalyzer: SpectrumAnalyzing, @unchecked Sendable {
    let submission: SpectrumSubmission
    private let context: UnsafeMutableRawPointer
    private(set) var shutdownCount = 0

    init(submitSucceeds: Bool) {
        context = .allocate(byteCount: 1, alignment: 1)
        context.storeBytes(of: submitSucceeds, as: Bool.self)
        submission = SpectrumSubmission(
            context: context,
            function: { context, _, _ in
                context.load(as: Bool.self)
            }
        )
    }

    deinit {
        context.deallocate()
    }

    func shutdown() {
        shutdownCount += 1
    }
}

@MainActor
final class SpectrumAnalyzerFactorySpy {
    var setupFails = false
    var submitSucceeds = true
    private(set) var sampleRates: [Double] = []
    private(set) var generations: [UInt64] = []
    private(set) var analyzers: [StubSpectrumAnalyzer] = []
    private(set) var deliveries: [
        @Sendable (SpectrumSnapshot, UInt64) -> Void
    ] = []

    var factory: SpectrumAnalyzerFactory {
        { [weak self] sampleRate, generation, deliver in
            guard let self else { return nil }
            sampleRates.append(sampleRate)
            generations.append(generation)
            guard !setupFails else { return nil }

            let analyzer = StubSpectrumAnalyzer(
                submitSucceeds: submitSucceeds
            )
            analyzers.append(analyzer)
            deliveries.append(deliver)
            return analyzer
        }
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
        let spy = SpectrumAnalyzerFactorySpy()
        let engine = makeEngine(spy)
        engine._setPlayingForTesting(true)

        engine._installSpectrumTap()
        #expect(engine.isSpectrumTapInstalled)
        #expect(spy.analyzers.count == 1)

        engine._installSpectrumTap()
        #expect(spy.analyzers.count == 1)

        engine._removeSpectrumTap()
        #expect(!engine.isSpectrumTapInstalled)
        #expect(spy.analyzers[0].shutdownCount == 1)

        engine._removeSpectrumTap()
        #expect(spy.analyzers[0].shutdownCount == 1)
    }

    @Test func enablementRespectsPlaybackState() {
        let stoppedSpy = SpectrumAnalyzerFactorySpy()
        let stopped = makeEngine(stoppedSpy)
        stopped.spectrumAnalysisEnabled = false
        stopped.spectrumAnalysisEnabled = true
        #expect(!stopped.isSpectrumTapInstalled)
        #expect(stoppedSpy.analyzers.isEmpty)

        let playingSpy = SpectrumAnalyzerFactorySpy()
        let playing = makeEngine(playingSpy)
        playing._setPlayingForTesting(true)
        playing._installSpectrumTap()
        playing.spectrumAnalysisEnabled = false
        #expect(!playing.isSpectrumTapInstalled)
        #expect(playingSpy.analyzers[0].shutdownCount == 1)
    }

    @Test func stoppingRemovesTapAndJoinsAnalyzer() {
        let spy = SpectrumAnalyzerFactorySpy()
        let engine = makeEngine(spy)
        engine._setPlayingForTesting(true)
        engine._installSpectrumTap()

        engine.stop()

        #expect(!engine.isPlaying)
        #expect(!engine.isSpectrumTapInstalled)
        #expect(spy.analyzers[0].shutdownCount == 1)
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
        submitEngine.onSpectrumSnapshot = { _ in
            submitSpectrumChanges += 1
        }
        submitEngine._installSpectrumTap()
        let analyzer = try #require(submitSpy.analyzers.first)
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
        engine.onSpectrumSnapshot = { received.append($0) }
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
        engine.onSpectrumSnapshot = { _ in deliveryCount += 1 }
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

    private func makeEngine(
        _ spy: SpectrumAnalyzerFactorySpy
    ) -> NoiseEngine {
        NoiseEngine(
            analyzerFactory: spy.factory,
            notificationCenter: NotificationCenter()
        )
    }
}
