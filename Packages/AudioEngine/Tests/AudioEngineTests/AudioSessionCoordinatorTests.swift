import Foundation
import Testing
@testable import AudioEngine

private enum SessionTestError: Error, Equatable {
    case category
    case activation
}

private final class SessionOperationProbe: @unchecked Sendable {
    enum Event: Equatable {
        case category
        case active(Bool)
    }

    private let lock = NSLock()
    private var events: [Event] = []
    private var mainThreadFlags: [Bool] = []
    var categoryError: Error?
    var activeTrueError: Error?
    var activeFalseError: Error?
    var blockedCategoryCallCount = 0
    var blockActiveValue: Bool?
    let categoryEntered = DispatchSemaphore(value: 0)
    let activeEntered = DispatchSemaphore(value: 0)
    let activeTrueEntered = DispatchSemaphore(value: 0)
    let activeFalseEntered = DispatchSemaphore(value: 0)
    let unblockCategory = DispatchSemaphore(value: 0)
    let unblockActive = DispatchSemaphore(value: 0)

    func setCategory() throws {
        let state = lock.withLock { () -> (Bool, Error?) in
            events.append(.category)
            mainThreadFlags.append(Thread.isMainThread)
            let shouldBlock = blockedCategoryCallCount > 0
            if shouldBlock { blockedCategoryCallCount -= 1 }
            return (shouldBlock, categoryError)
        }
        categoryEntered.signal()
        if state.0 { unblockCategory.wait() }
        if let error = state.1 { throw error }
    }

    func setActive(_ active: Bool) throws {
        let state = lock.withLock { () -> (Bool, Error?) in
            events.append(.active(active))
            mainThreadFlags.append(Thread.isMainThread)
            return (
                blockActiveValue == active,
                active ? activeTrueError : activeFalseError
            )
        }
        activeEntered.signal()
        if active {
            activeTrueEntered.signal()
        } else {
            activeFalseEntered.signal()
        }
        if state.0 { unblockActive.wait() }
        if let error = state.1 { throw error }
    }

    func snapshot() -> ([Event], [Bool]) {
        lock.withLock { (events, mainThreadFlags) }
    }
}

private func makeCoordinator(
    _ probe: SessionOperationProbe,
    didRegisterActivation: @escaping @Sendable () -> Void = {}
) -> AudioSessionCoordinator {
    AudioSessionCoordinator(
        label: "AudioSessionCoordinatorTests.\(UUID().uuidString)",
        setCategory: { try probe.setCategory() },
        setActive: { try probe.setActive($0) },
        didRegisterActivation: didRegisterActivation
    )
}

private func waitForSemaphore(
    _ semaphore: DispatchSemaphore,
    timeout: Duration = .seconds(2)
) async -> Bool {
    await withCheckedContinuation { continuation in
        DispatchQueue.global().async {
            continuation.resume(
                returning: semaphore.wait(
                    timeout: .now() + timeout.timeInterval
                ) == .success
            )
        }
    }
}

private func beginInactiveRequest(
    _ coordinator: AudioSessionCoordinator,
    policy: AudioSessionInactivePolicy
) async -> Task<Void, Never> {
    let completed = DispatchSemaphore(value: 0)
    let task = Task.detached {
        coordinator.requestInactive(policy)
        completed.signal()
    }
    #expect(await waitForSemaphore(completed))
    return task
}

private extension Duration {
    var timeInterval: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds)
            + TimeInterval(parts.attoseconds) / 1e18
    }
}

@Suite("Serialized audio session coordinator")
struct AudioSessionCoordinatorTests {
    @Test func activationRunsOffMainInCategoryThenActiveOrder() async throws {
        let probe = SessionOperationProbe()
        let coordinator = makeCoordinator(probe)

        try await coordinator.activate()
        await coordinator.waitUntilIdle()

        let snapshot = probe.snapshot()
        #expect(snapshot.0 == [.category, .active(true)])
        #expect(snapshot.1 == [false, false])
    }

    @Test func deactivationRunsOffMain() async throws {
        let probe = SessionOperationProbe()
        let coordinator = makeCoordinator(probe)
        try await coordinator.activate()

        coordinator.requestInactive(.deactivate)
        await coordinator.waitUntilIdle()

        let snapshot = probe.snapshot()
        #expect(snapshot.0 == [.category, .active(true), .active(false)])
        #expect(snapshot.1.allSatisfy { !$0 })
    }

    @Test func stopDuringBlockedActivationEndsInactive() async {
        let probe = SessionOperationProbe()
        probe.blockActiveValue = true
        let coordinator = makeCoordinator(probe)
        let activation = Task { try await coordinator.activate() }
        #expect(await waitForSemaphore(probe.activeTrueEntered))

        let request = await beginInactiveRequest(
            coordinator,
            policy: .deactivate
        )
        probe.unblockActive.signal()
        await request.value

        await #expect(throws: CancellationError.self) {
            try await activation.value
        }
        await coordinator.waitUntilIdle()
        #expect(probe.snapshot().0 == [.category, .active(true), .active(false)])
    }

    @Test func lateActivationSupersededBySystemManagedNeverDeactivates() async {
        let probe = SessionOperationProbe()
        probe.blockActiveValue = true
        let coordinator = makeCoordinator(probe)
        let activation = Task { try await coordinator.activate() }
        #expect(await waitForSemaphore(probe.activeTrueEntered))

        let request = await beginInactiveRequest(
            coordinator,
            policy: .systemManaged
        )
        probe.unblockActive.signal()
        await request.value

        await #expect(throws: CancellationError.self) {
            try await activation.value
        }
        await coordinator.waitUntilIdle()
        #expect(probe.snapshot().0 == [.category, .active(true)])
    }

    @Test func systemManagedInterruptionSupersedesPendingActivation() async {
        let probe = SessionOperationProbe()
        probe.blockedCategoryCallCount = 1
        let coordinator = makeCoordinator(probe)
        let activation = Task { try await coordinator.activate() }
        #expect(await waitForSemaphore(probe.categoryEntered))

        let request = await beginInactiveRequest(
            coordinator,
            policy: .systemManaged
        )
        probe.unblockCategory.signal()
        await request.value

        await #expect(throws: CancellationError.self) {
            try await activation.value
        }
        await coordinator.waitUntilIdle()
        #expect(probe.snapshot().0 == [.category])
    }

    @Test func queuedActivationSupersededBeforeExecutionNeverTouchesSession() async {
        let probe = SessionOperationProbe()
        probe.blockedCategoryCallCount = 1
        let registered = DispatchSemaphore(value: 0)
        let coordinator = makeCoordinator(probe) { registered.signal() }
        let first = Task { try await coordinator.activate() }
        #expect(await waitForSemaphore(registered))
        #expect(await waitForSemaphore(probe.categoryEntered))

        let second = Task { try await coordinator.activate() }
        #expect(await waitForSemaphore(registered))
        let request = await beginInactiveRequest(
            coordinator,
            policy: .deactivate
        )
        probe.unblockCategory.signal()
        await request.value

        await #expect(throws: CancellationError.self) { try await first.value }
        await #expect(throws: CancellationError.self) { try await second.value }
        await coordinator.waitUntilIdle()
        #expect(probe.snapshot().0 == [.category])
    }

    @Test func rapidStopStartSkipsObsoleteDeactivation() async throws {
        let probe = SessionOperationProbe()
        probe.blockedCategoryCallCount = 1
        let registered = DispatchSemaphore(value: 0)
        let coordinator = makeCoordinator(probe) { registered.signal() }
        let first = Task { try await coordinator.activate() }
        #expect(await waitForSemaphore(registered))
        #expect(await waitForSemaphore(probe.categoryEntered))
        let request = await beginInactiveRequest(
            coordinator,
            policy: .deactivate
        )
        let winner = Task { try await coordinator.activate() }
        #expect(await waitForSemaphore(registered))
        probe.unblockCategory.signal()
        await request.value

        await #expect(throws: CancellationError.self) { try await first.value }
        try await winner.value
        await coordinator.waitUntilIdle()
        #expect(probe.snapshot().0 == [.category, .category, .active(true)])
    }

    @Test func alreadyRunningDeactivationIsFollowedByWinningActivation() async throws {
        let probe = SessionOperationProbe()
        let coordinator = makeCoordinator(probe)
        try await coordinator.activate()
        probe.blockActiveValue = false
        coordinator.requestInactive(.deactivate)
        #expect(await waitForSemaphore(probe.activeFalseEntered))

        let winner = Task { try await coordinator.activate() }
        probe.unblockActive.signal()
        try await winner.value
        await coordinator.waitUntilIdle()

        #expect(
            probe.snapshot().0
                == [.category, .active(true), .active(false), .category, .active(true)]
        )
    }

    @Test func cancelingOlderActivationCannotDeactivateNewerActivation() async throws {
        let probe = SessionOperationProbe()
        probe.blockedCategoryCallCount = 1
        let registered = DispatchSemaphore(value: 0)
        let coordinator = makeCoordinator(probe) { registered.signal() }
        let old = Task { try await coordinator.activate() }
        #expect(await waitForSemaphore(registered))
        #expect(await waitForSemaphore(probe.categoryEntered))
        let winner = Task { try await coordinator.activate() }
        #expect(await waitForSemaphore(registered))
        old.cancel()
        probe.unblockCategory.signal()

        await #expect(throws: CancellationError.self) { try await old.value }
        try await winner.value
        await coordinator.waitUntilIdle()
        #expect(!probe.snapshot().0.contains(.active(false)))
    }

    @Test func cancelingCurrentActivationSchedulesCleanup() async {
        let probe = SessionOperationProbe()
        probe.blockActiveValue = true
        let coordinator = makeCoordinator(probe)
        let activation = Task { try await coordinator.activate() }
        #expect(await waitForSemaphore(probe.activeTrueEntered))

        activation.cancel()
        probe.unblockActive.signal()

        await #expect(throws: CancellationError.self) {
            try await activation.value
        }
        await coordinator.waitUntilIdle()
        #expect(probe.snapshot().0 == [.category, .active(true), .active(false)])
    }

    @Test func cancellationBeforeActivationBeginsNeverRegistersActiveIntent() async {
        let probe = SessionOperationProbe()
        let coordinator = makeCoordinator(probe)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await coordinator.activate()
        }

        await #expect(throws: CancellationError.self) { try await task.value }
        await coordinator.waitUntilIdle()
        #expect(probe.snapshot().0.isEmpty)
    }

    @Test func cancellationBetweenRegistrationAndEnqueueCleansIntent() async {
        let probe = SessionOperationProbe()
        let registered = DispatchSemaphore(value: 0)
        let continueEnqueue = DispatchSemaphore(value: 0)
        let cancellationObserved = DispatchSemaphore(value: 0)
        let coordinator = AudioSessionCoordinator(
            label: "AudioSessionCoordinatorTests.registrationRace",
            setCategory: { try probe.setCategory() },
            setActive: { try probe.setActive($0) },
            didRegisterActivation: {
                registered.signal()
                continueEnqueue.wait()
            },
            didCancelActivation: { cancellationObserved.signal() }
        )
        let task = Task.detached { try await coordinator.activate() }
        #expect(await waitForSemaphore(registered))

        let cancellation = Task.detached { task.cancel() }
        #expect(await waitForSemaphore(cancellationObserved))
        continueEnqueue.signal()
        await cancellation.value

        await #expect(throws: CancellationError.self) { try await task.value }
        await coordinator.waitUntilIdle()
        #expect(probe.snapshot().0.isEmpty)
    }

    @Test func staleCategoryFailureBecomesCancellationError() async {
        let probe = SessionOperationProbe()
        probe.blockedCategoryCallCount = 1
        probe.categoryError = SessionTestError.category
        let coordinator = makeCoordinator(probe)
        let activation = Task { try await coordinator.activate() }
        #expect(await waitForSemaphore(probe.categoryEntered))
        let request = await beginInactiveRequest(
            coordinator,
            policy: .deactivate
        )
        probe.unblockCategory.signal()
        await request.value

        await #expect(throws: CancellationError.self) { try await activation.value }
    }

    @Test func currentCategoryFailureRemainsReal() async {
        let probe = SessionOperationProbe()
        probe.categoryError = SessionTestError.category
        let coordinator = makeCoordinator(probe)

        await #expect(throws: SessionTestError.category) {
            try await coordinator.activate()
        }
    }

    @Test func staleActivationFailureBecomesCancellationError() async {
        let probe = SessionOperationProbe()
        probe.blockActiveValue = true
        probe.activeTrueError = SessionTestError.activation
        let coordinator = makeCoordinator(probe)
        let activation = Task { try await coordinator.activate() }
        #expect(await waitForSemaphore(probe.activeTrueEntered))
        let request = await beginInactiveRequest(
            coordinator,
            policy: .deactivate
        )
        probe.unblockActive.signal()
        await request.value

        await #expect(throws: CancellationError.self) { try await activation.value }
        await coordinator.waitUntilIdle()
        #expect(probe.snapshot().0 == [.category, .active(true), .active(false)])
    }

    @Test func currentActivationFailureRemainsReal() async {
        let probe = SessionOperationProbe()
        probe.activeTrueError = SessionTestError.activation
        let coordinator = makeCoordinator(probe)

        await #expect(throws: SessionTestError.activation) {
            try await coordinator.activate()
        }
    }

    @Test func requestInactiveReturnsWhileSessionOperationIsBlocked() async {
        let probe = SessionOperationProbe()
        probe.blockActiveValue = true
        let coordinator = makeCoordinator(probe)
        let activation = Task { try await coordinator.activate() }
        #expect(await waitForSemaphore(probe.activeTrueEntered))

        let request = await beginInactiveRequest(
            coordinator,
            policy: .deactivate
        )
        probe.unblockActive.signal()
        await request.value
        _ = try? await activation.value
        await coordinator.waitUntilIdle()
    }
}
