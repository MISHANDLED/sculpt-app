import Dispatch
import Foundation
import Testing
@testable import AudioEngine

final class SpectrumAnalyzerDeliveryState: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    func value() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

final class SpectrumAnalyzerDeinitObserver: @unchecked Sendable {
    let semaphore: DispatchSemaphore

    init(semaphore: DispatchSemaphore) {
        self.semaphore = semaphore
    }

    func keepAlive() {}

    deinit {
        semaphore.signal()
    }
}

@Suite("Spectrum analyzer worker", .serialized)
struct SpectrumAnalyzerTests {
    @Test func pollingWorkerDeliversSnapshotWithGeneration() async throws {
        let samples = SpectrumTestSignal.sine(
            frequency: 1_000,
            sampleRate: 44_100
        )

        await confirmation("spectrum delivered", expectedCount: 1) { delivered in
            let analyzer = SpectrumAnalyzer(
                sampleRate: 44_100,
                generation: 42,
                pollInterval: .milliseconds(1)
            ) { snapshot, generation in
                #expect(generation == 42)
                #expect(snapshot.bands[4] > 0)
                delivered()
            }!

            samples.withUnsafeBufferPointer { buffer in
                _ = analyzer.submission.submit(
                    buffer.baseAddress!,
                    count: buffer.count
                )
            }
            // AVAudioUnit construction in parallel engine tests can briefly
            // saturate simulator workers; leave enough time for this polling
            // thread to be scheduled under a full-suite run.
            try? await Task.sleep(for: .milliseconds(250))
            analyzer.shutdown()
        }
    }

    @Test func analyzerAccumulatesArbitraryCallbackChunks() async {
        let samples = SpectrumTestSignal.sine(
            frequency: 500,
            sampleRate: 44_100
        )

        await confirmation("one complete window", expectedCount: 1) { delivered in
            let analyzer = SpectrumAnalyzer(
                sampleRate: 44_100,
                generation: 7,
                pollInterval: .milliseconds(1)
            ) { _, generation in
                #expect(generation == 7)
                delivered()
            }!

            samples[0..<777].withUnsafeBufferPointer { buffer in
                _ = analyzer.submission.submit(buffer.baseAddress!, count: buffer.count)
            }
            samples[777..<3_000].withUnsafeBufferPointer { buffer in
                _ = analyzer.submission.submit(buffer.baseAddress!, count: buffer.count)
            }
            samples[3_000..<4_096].withUnsafeBufferPointer { buffer in
                _ = analyzer.submission.submit(buffer.baseAddress!, count: buffer.count)
            }
            try? await Task.sleep(for: .milliseconds(50))
            analyzer.shutdown()
        }
    }

    @Test func shutdownJoinsWorkerAndIsIdempotent() async throws {
        let state = SpectrumAnalyzerDeliveryState()
        let analyzer = SpectrumAnalyzer(
            sampleRate: 44_100,
            generation: 1,
            pollInterval: .milliseconds(1)
        ) { _, _ in
            state.increment()
        }!
        let submission = analyzer.submission
        let samples = SpectrumTestSignal.sine(
            frequency: 2_000,
            sampleRate: 44_100
        )

        samples.withUnsafeBufferPointer { buffer in
            _ = submission.submit(buffer.baseAddress!, count: buffer.count)
        }
        try await Task.sleep(for: .milliseconds(20))
        analyzer.shutdown()
        analyzer.shutdown()
        let countAtShutdown = state.value()

        samples.withUnsafeBufferPointer { buffer in
            _ = submission.submit(buffer.baseAddress!, count: buffer.count)
        }
        try await Task.sleep(for: .milliseconds(20))
        #expect(state.value() == countAtShutdown)
    }

    @Test func shutdownWaitsForInFlightDeliveryBeforeDestruction() async throws {
        let enteredDelivery = DispatchSemaphore(value: 0)
        let releaseDelivery = DispatchSemaphore(value: 0)
        let enteredShutdownJoin = DispatchSemaphore(value: 0)
        let shutdownState = SpectrumAnalyzerDeliveryState()
        let analyzer = SpectrumAnalyzer(
            sampleRate: 44_100,
            generation: 9,
            pollInterval: .milliseconds(1),
            beforeShutdownJoin: {
                enteredShutdownJoin.signal()
            }
        ) { _, _ in
            enteredDelivery.signal()
            releaseDelivery.wait()
        }!
        let samples = SpectrumTestSignal.sine(
            frequency: 4_000,
            sampleRate: 44_100
        )
        samples.withUnsafeBufferPointer { buffer in
            _ = analyzer.submission.submit(
                buffer.baseAddress!,
                count: buffer.count
            )
        }

        let entered = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(
                    returning: enteredDelivery.wait(timeout: .now() + 1)
                )
            }
        }
        #expect(entered == .success)
        let shutdown = Task.detached {
            analyzer.shutdown()
            shutdownState.increment()
        }
        let shutdownReachedJoin = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(
                    returning: enteredShutdownJoin.wait(timeout: .now() + 1)
                )
            }
        }
        #expect(shutdownReachedJoin == .success)
        #expect(shutdownState.value() == 0)

        releaseDelivery.signal()
        await shutdown.value
        #expect(shutdownState.value() == 1)
    }

    @Test func concurrentShutdownCallsBothWaitForInFlightDelivery() async throws {
        let enteredDelivery = DispatchSemaphore(value: 0)
        let releaseDelivery = DispatchSemaphore(value: 0)
        let enteredShutdownJoin = DispatchSemaphore(value: 0)
        let shutdownState = SpectrumAnalyzerDeliveryState()
        let analyzer = SpectrumAnalyzer(
            sampleRate: 44_100,
            generation: 10,
            pollInterval: .milliseconds(1),
            beforeShutdownJoin: {
                enteredShutdownJoin.signal()
            }
        ) { _, _ in
            enteredDelivery.signal()
            releaseDelivery.wait()
        }!
        let samples = SpectrumTestSignal.sine(
            frequency: 8_000,
            sampleRate: 44_100
        )
        samples.withUnsafeBufferPointer { buffer in
            _ = analyzer.submission.submit(
                buffer.baseAddress!,
                count: buffer.count
            )
        }

        let entered = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(
                    returning: enteredDelivery.wait(timeout: .now() + 1)
                )
            }
        }
        #expect(entered == .success)

        let firstShutdown = Task.detached {
            analyzer.shutdown()
            shutdownState.increment()
        }
        let secondShutdown = Task.detached {
            analyzer.shutdown()
            shutdownState.increment()
        }
        let firstReachedJoin = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(
                    returning: enteredShutdownJoin.wait(timeout: .now() + 1)
                )
            }
        }
        let secondReachedJoin = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(
                    returning: enteredShutdownJoin.wait(timeout: .now() + 1)
                )
            }
        }
        #expect(firstReachedJoin == .success)
        #expect(secondReachedJoin == .success)
        #expect(shutdownState.value() == 0)

        releaseDelivery.signal()
        await firstShutdown.value
        await secondShutdown.value
        #expect(shutdownState.value() == 2)
    }

    @Test func deinitOnWorkerQueueDoesNotTrap() async {
        let enteredDelivery = DispatchSemaphore(value: 0)
        let releaseDelivery = DispatchSemaphore(value: 0)
        let didDeinit = DispatchSemaphore(value: 0)
        var observer: SpectrumAnalyzerDeinitObserver? =
            SpectrumAnalyzerDeinitObserver(semaphore: didDeinit)
        var analyzer: SpectrumAnalyzer? = SpectrumAnalyzer(
            sampleRate: 44_100,
            generation: 11,
            pollInterval: .milliseconds(1)
        ) { [observer] _, _ in
            observer?.keepAlive()
            enteredDelivery.signal()
            releaseDelivery.wait()
        }
        let submission = analyzer!.submission
        observer = nil
        let samples = SpectrumTestSignal.sine(
            frequency: 125,
            sampleRate: 44_100
        )
        samples.withUnsafeBufferPointer { buffer in
            _ = submission.submit(buffer.baseAddress!, count: buffer.count)
        }

        let entered = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(
                    returning: enteredDelivery.wait(timeout: .now() + 1)
                )
            }
        }
        #expect(entered == .success)

        analyzer = nil
        releaseDelivery.signal()

        let destroyed = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(
                    returning: didDeinit.wait(timeout: .now() + 1)
                )
            }
        }
        #expect(destroyed == .success)
    }

    @Test func invalidSampleRateFailsSetupWithoutAWorker() {
        let analyzer = SpectrumAnalyzer(
            sampleRate: 0,
            generation: 1,
            pollInterval: .milliseconds(1)
        ) { _, _ in }
        #expect(analyzer == nil)
    }
}
