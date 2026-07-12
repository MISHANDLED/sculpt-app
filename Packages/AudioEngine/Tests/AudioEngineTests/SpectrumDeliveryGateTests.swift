import Foundation
import Testing
@testable import AudioEngine

final class SpectrumMainJobRecorder: @unchecked Sendable {
    typealias Job = @MainActor @Sendable () -> Void

    private let lock = NSLock()
    private var jobs: [Job] = []
    private var scheduledCount = 0

    var schedule: SpectrumDeliveryGate.Scheduler {
        { [weak self] job in
            guard let self else { return }
            lock.withLock {
                self.jobs.append(job)
                self.scheduledCount += 1
            }
        }
    }

    var count: Int {
        lock.withLock { jobs.count }
    }

    var totalScheduled: Int {
        lock.withLock { scheduledCount }
    }

    @MainActor
    func runNext() {
        let job = lock.withLock {
            jobs.isEmpty ? nil : jobs.removeFirst()
        }
        guard let job else {
            Issue.record("Expected a scheduled spectrum-delivery job")
            return
        }
        job()
    }
}

@MainActor
private final class SpectrumDeliveryRecorder {
    private(set) var deliveries: [SpectrumDelivery] = []

    func append(_ delivery: SpectrumDelivery) {
        deliveries.append(delivery)
    }
}

@MainActor
private final class SpectrumGateHolder {
    var gate: SpectrumDeliveryGate?
}

@MainActor
@Suite("Spectrum delivery gate")
struct SpectrumDeliveryGateTests {
    private let clock = ContinuousClock()

    @Test func blockedMainActorSchedulesOnceAndKeepsNewest() {
        let scheduler = SpectrumMainJobRecorder()
        let received = SpectrumDeliveryRecorder()
        let gate = SpectrumDeliveryGate(
            schedule: scheduler.schedule,
            consume: { received.append($0) }
        )
        gate.activate(generation: 7)

        for index in 0..<128 {
            let level = Float(index) / 127
            gate.submit(
                snapshot(level),
                generation: 7,
                analyzedAt: clock.now.advanced(by: .milliseconds(index))
            )
        }
        let newestAt = clock.now.advanced(by: .seconds(2))
        let newest = snapshot(0.91)
        gate.submit(newest, generation: 7, analyzedAt: newestAt)

        #expect(scheduler.count == 1)
        #expect(scheduler.totalScheduled == 1)
        scheduler.runNext()
        #expect(received.deliveries.map(\.snapshot) == [newest])
        #expect(received.deliveries.map(\.analyzedAt) == [newestAt])
        #expect(scheduler.count == 0)
    }

    @Test func oldGenerationCannotDisplaceCurrentPendingValue() {
        let scheduler = SpectrumMainJobRecorder()
        let received = SpectrumDeliveryRecorder()
        let gate = SpectrumDeliveryGate(
            schedule: scheduler.schedule,
            consume: { received.append($0) }
        )
        gate.activate(generation: 1)
        gate.submit(snapshot(0.1), generation: 1, analyzedAt: clock.now)
        gate.deactivate()
        gate.activate(generation: 2)
        let current = snapshot(0.8)
        let currentAt = clock.now.advanced(by: .milliseconds(20))
        gate.submit(current, generation: 2, analyzedAt: currentAt)
        gate.submit(
            snapshot(1),
            generation: 1,
            analyzedAt: currentAt.advanced(by: .milliseconds(1))
        )

        #expect(scheduler.count == 1)
        scheduler.runNext()
        #expect(received.deliveries == [
            SpectrumDelivery(
                snapshot: current,
                generation: 2,
                analyzedAt: currentAt
            )
        ])
    }

    @Test func deactivateDropsPendingDelivery() {
        let scheduler = SpectrumMainJobRecorder()
        let received = SpectrumDeliveryRecorder()
        let gate = SpectrumDeliveryGate(
            schedule: scheduler.schedule,
            consume: { received.append($0) }
        )
        gate.activate(generation: 4)
        gate.submit(snapshot(0.7), generation: 4, analyzedAt: clock.now)

        gate.deactivate()
        scheduler.runNext()

        #expect(received.deliveries.isEmpty)
        #expect(scheduler.count == 0)
        #expect(scheduler.totalScheduled == 1)
    }

    @Test func queuedDrainCanServeReactivatedGeneration() {
        let scheduler = SpectrumMainJobRecorder()
        let received = SpectrumDeliveryRecorder()
        let gate = SpectrumDeliveryGate(
            schedule: scheduler.schedule,
            consume: { received.append($0) }
        )
        gate.activate(generation: 10)
        gate.submit(snapshot(0.2), generation: 10, analyzedAt: clock.now)
        gate.deactivate()
        gate.activate(generation: 11)
        let replacement = snapshot(0.6)
        gate.submit(replacement, generation: 11, analyzedAt: clock.now)

        #expect(scheduler.totalScheduled == 1)
        scheduler.runNext()

        #expect(received.deliveries.map(\.snapshot) == [replacement])
        #expect(received.deliveries.map(\.generation) == [11])
    }

    @Test func submitDuringConsumeSchedulesExactlyOneFollowUpDrain() {
        let scheduler = SpectrumMainJobRecorder()
        let received = SpectrumDeliveryRecorder()
        let holder = SpectrumGateHolder()
        let second = snapshot(0.9)
        let secondAt = clock.now.advanced(by: .milliseconds(10))
        let gate = SpectrumDeliveryGate(
            schedule: scheduler.schedule,
            consume: { delivery in
                received.append(delivery)
                if received.deliveries.count == 1 {
                    holder.gate?.submit(
                        second,
                        generation: 3,
                        analyzedAt: secondAt
                    )
                }
            }
        )
        holder.gate = gate
        gate.activate(generation: 3)
        gate.submit(snapshot(0.3), generation: 3, analyzedAt: clock.now)

        scheduler.runNext()

        #expect(received.deliveries.count == 1)
        #expect(scheduler.count == 1)
        #expect(scheduler.totalScheduled == 2)
        scheduler.runNext()
        #expect(received.deliveries.map(\.snapshot) == [snapshot(0.3), second])
        #expect(scheduler.count == 0)
        #expect(scheduler.totalScheduled == 2)
    }

    @Test func invalidationDuringConsumeRejectsSameGenerationFollowUp() {
        let scheduler = SpectrumMainJobRecorder()
        let received = SpectrumDeliveryRecorder()
        let holder = SpectrumGateHolder()
        let gate = SpectrumDeliveryGate(
            schedule: scheduler.schedule,
            consume: { delivery in
                received.append(delivery)
                holder.gate?.deactivate()
                holder.gate?.submit(
                    self.snapshot(1),
                    generation: 42,
                    analyzedAt: self.clock.now
                )
            }
        )
        holder.gate = gate
        gate.activate(generation: 42)
        gate.submit(snapshot(0.5), generation: 42, analyzedAt: clock.now)

        scheduler.runNext()

        #expect(received.deliveries.map(\.snapshot) == [snapshot(0.5)])
        #expect(scheduler.count == 0)
        #expect(scheduler.totalScheduled == 1)
    }

    @Test func synchronousSchedulerDoesNotDeadlockOrLoseDelivery() {
        let received = SpectrumDeliveryRecorder()
        let gate = SpectrumDeliveryGate(
            schedule: { job in
                MainActor.assumeIsolated { job() }
            },
            consume: { received.append($0) }
        )
        let analyzedAt = clock.now
        let value = snapshot(0.4)
        gate.activate(generation: 5)

        gate.submit(value, generation: 5, analyzedAt: analyzedAt)

        #expect(received.deliveries == [
            SpectrumDelivery(
                snapshot: value,
                generation: 5,
                analyzedAt: analyzedAt
            )
        ])
    }

    private func snapshot(_ value: Float) -> SpectrumSnapshot {
        SpectrumSnapshot(
            bands: SIMD8<Float>(repeating: value),
            rms: value,
            peak: value
        )
    }
}
