import AVFoundation
import Foundation
import Testing
@testable import AudioEngine

enum EngineSessionTestError: Error {
    case activation
    case graphStart
}

final class EngineSessionCoordinatorProbe: AudioSessionCoordinating,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var activationResults: [Result<Void, Error>] = []
    private var waiters: [CheckedContinuation<Void, Error>] = []
    private var inactivePolicies: [AudioSessionInactivePolicy] = []
    private var activationCallCount = 0
    let activationEntered = DispatchSemaphore(value: 0)

    func activate() async throws {
        try await withCheckedThrowingContinuation { continuation in
            let result = lock.withLock { () -> Result<Void, Error>? in
                activationCallCount += 1
                if activationResults.isEmpty {
                    waiters.append(continuation)
                    return nil
                }
                return activationResults.removeFirst()
            }
            activationEntered.signal()
            if let result { continuation.resume(with: result) }
        }
    }

    func requestInactive(_ policy: AudioSessionInactivePolicy) {
        lock.withLock { inactivePolicies.append(policy) }
    }

    func waitUntilIdle() async {}

    func completeNext(_ result: Result<Void, Error>) {
        let waiter = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            guard !waiters.isEmpty else {
                activationResults.append(result)
                return nil
            }
            return waiters.removeFirst()
        }
        waiter?.resume(with: result)
    }

    func policies() -> [AudioSessionInactivePolicy] {
        lock.withLock { inactivePolicies }
    }

    func activationCount() -> Int {
        lock.withLock { activationCallCount }
    }
}

@MainActor
final class PlaybackGraphProbe: @unchecked Sendable {
    var running = false
    var startCount = 0
    var stopCount = 0
    var startError: Error?

    var hooks: NoiseEnginePlaybackGraphHooks {
        NoiseEnginePlaybackGraphHooks(
            isRunning: { [weak self] _ in self?.running == true },
            start: { [weak self] _ in
                guard let self else { return }
                if let startError { throw startError }
                startCount += 1
                running = true
            },
            stop: { [weak self] _ in
                self?.stopCount += 1
                self?.running = false
            }
        )
    }
}

func waitForActivation(
    _ probe: EngineSessionCoordinatorProbe
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
@Suite("Session deactivation policy")
struct NoiseEngineSessionTests {

    @Test func activationFailureClearsPlaybackRequest() async {
        let session = EngineSessionCoordinatorProbe()
        session.completeNext(.failure(EngineSessionTestError.activation))
        let graph = PlaybackGraphProbe()
        let engine = NoiseEngine(
            notificationCenter: NotificationCenter(),
            audioSessionCoordinator: session,
            playbackGraphHooks: graph.hooks
        )
        engine.spectrumAnalysisEnabled = false

        await #expect(throws: EngineSessionTestError.self) {
            try await engine.start()
        }

        #expect(!engine.isPlaybackRequested)
        #expect(!engine.isPlaying)
        #expect(graph.startCount == 0)
    }

    @Test func blockedOldStartCannotStartGraphAfterStopAndNewStart() async throws {
        let session = EngineSessionCoordinatorProbe()
        let graph = PlaybackGraphProbe()
        let engine = NoiseEngine(
            notificationCenter: NotificationCenter(),
            audioSessionCoordinator: session,
            playbackGraphHooks: graph.hooks
        )
        engine.spectrumAnalysisEnabled = false
        let old = Task { try await engine.start() }
        #expect(await waitForActivation(session))

        engine.stop()
        let newest = Task { try await engine.start() }
        #expect(await waitForActivation(session))
        session.completeNext(.success(()))
        await #expect(throws: CancellationError.self) { try await old.value }
        #expect(graph.startCount == 0)

        session.completeNext(.success(()))
        try await newest.value
        #expect(graph.startCount == 1)
        #expect(engine.isPlaying)
        #expect(engine.isPlaybackRequested)
    }

    @Test func manualStopInvalidatesRequestedPlaybackSynchronously() async {
        let session = EngineSessionCoordinatorProbe()
        let graph = PlaybackGraphProbe()
        let engine = NoiseEngine(
            notificationCenter: NotificationCenter(),
            audioSessionCoordinator: session,
            playbackGraphHooks: graph.hooks
        )
        let start = Task { try await engine.start() }
        #expect(await waitForActivation(session))
        #expect(engine.isPlaybackRequested)

        engine.stop()

        #expect(!engine.isPlaybackRequested)
        session.completeNext(.success(()))
        _ = try? await start.value
    }

    @Test func graphStartFailureRequestsInactiveAndClearsRequest() async {
        let session = EngineSessionCoordinatorProbe()
        session.completeNext(.success(()))
        let graph = PlaybackGraphProbe()
        graph.startError = EngineSessionTestError.graphStart
        let engine = NoiseEngine(
            notificationCenter: NotificationCenter(),
            audioSessionCoordinator: session,
            playbackGraphHooks: graph.hooks
        )
        engine.spectrumAnalysisEnabled = false

        await #expect(throws: EngineSessionTestError.graphStart) {
            try await engine.start()
        }

        #expect(!engine.isPlaybackRequested)
        #expect(!engine.isPlaying)
        #expect(session.policies() == [.deactivate])
    }

    @Test func manualStopDeactivatesSession() {
        let engine = NoiseEngine()
        engine.stop()
        #expect(engine._lastStopDeactivatedSession == true)
    }

    @Test func interruptionStopKeepsSessionActive() async {
        let engine = NoiseEngine()
        await engine._applyInterruption(type: .began, options: [])
        #expect(engine._lastStopDeactivatedSession == false)
    }

    @Test func routeNotificationHopsToMainActor() async {
        let center = NotificationCenter()
        let engine = NoiseEngine(notificationCenter: center)
        engine._setPlayingForTesting(true)

        await Task.detached {
            center.post(
                name: AVAudioSession.routeChangeNotification,
                object: nil,
                userInfo: [
                    AVAudioSessionRouteChangeReasonKey:
                        AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
                ]
            )
        }.value
        for _ in 0..<20 where engine.isPlaying { await Task.yield() }
        #expect(!engine.isPlaying)
        #expect(engine._lastStopDeactivatedSession == true)
    }
}
