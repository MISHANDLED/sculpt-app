import AVFoundation
import Foundation

public enum AudioSessionInactivePolicy: Sendable, Equatable {
    case deactivate
    case systemManaged
}

public protocol AudioSessionCoordinating: Sendable {
    func activate() async throws
    func requestInactive(_ policy: AudioSessionInactivePolicy)
    func waitUntilIdle() async
}

public final class AudioSessionCoordinator: AudioSessionCoordinating,
    @unchecked Sendable
{
    private final class ActivationTicket: @unchecked Sendable {
        private enum State {
            case pending
            case registered(UInt64)
            case cancelled(UInt64?)
        }

        private let lock = NSLock()
        private var state: State = .pending

        func register(_ generation: UInt64) -> Bool {
            lock.withLock {
                guard case .pending = state else { return false }
                state = .registered(generation)
                return true
            }
        }

        func cancel() -> UInt64? {
            lock.withLock {
                switch state {
                case .pending:
                    state = .cancelled(nil)
                    return nil
                case .registered(let generation):
                    state = .cancelled(generation)
                    return generation
                case .cancelled(let generation):
                    return generation
                }
            }
        }

        var isCancelled: Bool {
            lock.withLock {
                if case .cancelled = state { return true }
                return false
            }
        }
    }

    public static let shared = AudioSessionCoordinator(
        label: "com.sculptor.audio-session",
        setCategory: {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default
            )
        },
        setActive: {
            try AVAudioSession.sharedInstance().setActive($0)
        }
    )

    private enum DesiredState: Equatable {
        case active(UInt64)
        case inactive(UInt64, AudioSessionInactivePolicy)
    }

    private let lock = NSLock()
    private var nextGeneration: UInt64 = 0
    private var desiredState: DesiredState = .inactive(0, .deactivate)

    private let queue: DispatchQueue
    private let setCategory: @Sendable () throws -> Void
    private let setActive: @Sendable (Bool) throws -> Void
    private let didRegisterActivation: @Sendable () -> Void
    private let didCancelActivation: @Sendable () -> Void

    // Queue-confined. The serial queue is the sole owner of applied state.
    private var appliedActive = false

    init(
        label: String,
        setCategory: @escaping @Sendable () throws -> Void,
        setActive: @escaping @Sendable (Bool) throws -> Void,
        didRegisterActivation: @escaping @Sendable () -> Void = {},
        didCancelActivation: @escaping @Sendable () -> Void = {}
    ) {
        queue = DispatchQueue(label: label)
        self.setCategory = setCategory
        self.setActive = setActive
        self.didRegisterActivation = didRegisterActivation
        self.didCancelActivation = didCancelActivation
    }

    public func activate() async throws {
        try Task.checkCancellation()
        let ticket = ActivationTicket()

        do {
            try await withTaskCancellationHandler {
                try Task.checkCancellation()
                try await withCheckedThrowingContinuation { continuation in
                    enqueueActivation(
                        ticket: ticket,
                        continuation: continuation
                    )
                }
            } onCancel: { [self] in
                let generation = ticket.cancel()
                didCancelActivation()
                guard let generation else { return }
                cancelActivationIfCurrent(generation)
            }
            try Task.checkCancellation()
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
    }

    public func requestInactive(_ policy: AudioSessionInactivePolicy) {
        lock.withLock {
            nextGeneration += 1
            desiredState = .inactive(nextGeneration, policy)
            let generation = nextGeneration
            queue.async { [self] in
                executeInactive(generation: generation, policy: policy)
            }
        }
    }

    public func waitUntilIdle() async {
        await withCheckedContinuation { continuation in
            lock.withLock {
                queue.async {
                    continuation.resume()
                }
            }
        }
    }

    private func enqueueActivation(
        ticket: ActivationTicket,
        continuation: CheckedContinuation<Void, Error>
    ) {
        var canceledBeforeEnqueue = false
        lock.withLock {
            nextGeneration += 1
            let generation = nextGeneration
            guard ticket.register(generation) else {
                canceledBeforeEnqueue = true
                return
            }
            desiredState = .active(generation)

            // This seam is inert in production. It makes the otherwise tiny
            // registration/enqueue cancellation window deterministic in tests.
            didRegisterActivation()
            if ticket.isCancelled {
                nextGeneration += 1
                let cleanupGeneration = nextGeneration
                desiredState = .inactive(cleanupGeneration, .deactivate)
                queue.async { [self] in
                    executeInactive(
                        generation: cleanupGeneration,
                        policy: .deactivate
                    )
                }
                canceledBeforeEnqueue = true
                return
            }

            queue.async { [self] in
                executeActivation(
                    generation: generation,
                    continuation: continuation
                )
            }
        }
        if canceledBeforeEnqueue {
            continuation.resume(throwing: CancellationError())
        }
    }

    private func cancelActivationIfCurrent(_ generation: UInt64) {
        lock.withLock {
            guard desiredState == .active(generation) else { return }
            nextGeneration += 1
            desiredState = .inactive(nextGeneration, .deactivate)
            let cleanupGeneration = nextGeneration
            queue.async { [self] in
                executeInactive(
                    generation: cleanupGeneration,
                    policy: .deactivate
                )
            }
        }
    }

    private func executeActivation(
        generation: UInt64,
        continuation: CheckedContinuation<Void, Error>
    ) {
        guard isCurrentActivation(generation) else {
            continuation.resume(throwing: CancellationError())
            return
        }

        do {
            try setCategory()
            guard isCurrentActivation(generation) else {
                continuation.resume(throwing: CancellationError())
                return
            }

            do {
                appliedActive = true
                try setActive(true)
            } catch {
                guard isCurrentActivation(generation) else {
                    cleanUpSupersededActivationIfNeeded()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                continuation.resume(throwing: error)
                return
            }

            guard isCurrentActivation(generation) else {
                cleanUpSupersededActivationIfNeeded()
                continuation.resume(throwing: CancellationError())
                return
            }
            continuation.resume()
        } catch {
            if isCurrentActivation(generation) {
                continuation.resume(throwing: error)
            } else {
                continuation.resume(throwing: CancellationError())
            }
        }
    }

    private func cleanUpSupersededActivationIfNeeded() {
        switch snapshotDesiredState() {
        case .inactive(_, .deactivate):
            do {
                try setActive(false)
                appliedActive = false
            } catch {
                // Keep the state active/uncertain so a later inactive request
                // can retry deactivation.
            }
        case .inactive(_, .systemManaged):
            appliedActive = false
        case .active:
            // A newer activation owns the now-active session. Never let an
            // older request's cancellation deactivate it.
            break
        }
    }

    private func executeInactive(
        generation: UInt64,
        policy: AudioSessionInactivePolicy
    ) {
        guard snapshotDesiredState() == .inactive(generation, policy) else {
            return
        }

        switch policy {
        case .deactivate:
            guard appliedActive else { return }
            do {
                try setActive(false)
                appliedActive = false
            } catch {
                // A later inactive generation may retry.
            }
        case .systemManaged:
            appliedActive = false
        }
    }

    private func isCurrentActivation(_ generation: UInt64) -> Bool {
        lock.withLock { desiredState == .active(generation) }
    }

    private func snapshotDesiredState() -> DesiredState {
        lock.withLock { desiredState }
    }
}
