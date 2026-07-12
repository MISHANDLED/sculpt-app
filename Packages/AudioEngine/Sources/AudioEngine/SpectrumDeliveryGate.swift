import Foundation

struct SpectrumDelivery: Equatable, Sendable {
    let snapshot: SpectrumSnapshot
    let generation: UInt64
    let analyzedAt: ContinuousClock.Instant
}

final class SpectrumDeliveryGate: @unchecked Sendable {
    typealias Scheduler = @Sendable (
        @escaping @MainActor @Sendable () -> Void
    ) -> Void

    static let defaultSchedule: Scheduler = { job in
        Task { @MainActor in
            job()
        }
    }

    private let lock = NSLock()
    private let schedule: Scheduler
    private let consume: @MainActor @Sendable (SpectrumDelivery) -> Void
    private var activeGeneration: UInt64?
    private var pending: SpectrumDelivery?
    private var drainScheduled = false

    init(
        schedule: @escaping Scheduler = SpectrumDeliveryGate.defaultSchedule,
        consume: @escaping @MainActor @Sendable (SpectrumDelivery) -> Void
    ) {
        self.schedule = schedule
        self.consume = consume
    }

    @MainActor
    func activate(generation: UInt64) {
        lock.withLock {
            activeGeneration = generation
            pending = nil
        }
    }

    @MainActor
    func deactivate() {
        lock.withLock {
            activeGeneration = nil
            pending = nil
        }
    }

    func submit(
        _ snapshot: SpectrumSnapshot,
        generation: UInt64,
        analyzedAt: ContinuousClock.Instant
    ) {
        let delivery = SpectrumDelivery(
            snapshot: snapshot,
            generation: generation,
            analyzedAt: analyzedAt
        )
        let shouldSchedule = lock.withLock { () -> Bool in
            guard activeGeneration == generation else { return false }
            pending = delivery
            guard !drainScheduled else { return false }
            drainScheduled = true
            return true
        }
        if shouldSchedule {
            scheduleDrain()
        }
    }

    private func scheduleDrain() {
        schedule { [weak self] in
            self?.drainOne()
        }
    }

    @MainActor
    private func drainOne() {
        let delivery = lock.withLock { () -> SpectrumDelivery? in
            guard let candidate = pending,
                  activeGeneration == candidate.generation else {
                pending = nil
                return nil
            }
            pending = nil
            return candidate
        }

        if let delivery {
            consume(delivery)
        }

        let shouldContinue = lock.withLock { () -> Bool in
            guard let candidate = pending else {
                drainScheduled = false
                return false
            }
            guard activeGeneration == candidate.generation else {
                pending = nil
                drainScheduled = false
                return false
            }
            return true
        }
        if shouldContinue {
            scheduleDrain()
        }
    }
}
