import Darwin
import RealtimeAtomics

struct ClaimedSpectrumFrame: @unchecked Sendable {
    fileprivate let slot: Int
    let sequence: UInt64
    let samples: UnsafeBufferPointer<Float>
}

private struct SpectrumMailboxProducerControl {
    let accumulator: UnsafeMutablePointer<Float>
    let slot0: UnsafeMutablePointer<Float>
    let slot1: UnsafeMutablePointer<Float>
    let state0: OpaquePointer
    let state1: OpaquePointer
    var accumulatedCount: Int
    var nextSequence: UInt64
    var sequence0: UInt64
    var sequence1: UInt64
}

@_cdecl("rt_spectrum_mailbox_submit")
@inline(never)
public func rtSpectrumMailboxSubmitC(
    _ context: UnsafeMutableRawPointer,
    _ samples: UnsafePointer<Float>,
    _ count: Int
) -> Bool {
    SpectrumMailbox.submit(
        context: context,
        samples: samples,
        count: count
    )
}

final class SpectrumMailbox: @unchecked Sendable {
    static let sampleCount = 4_096

    private static let free: UInt8 = 0
    private static let writing: UInt8 = 1
    private static let ready: UInt8 = 2
    private static let reading: UInt8 = 3

    private let producer: UnsafeMutablePointer<SpectrumMailboxProducerControl>

    init?() {
        guard let firstState = rt_atomic_u8_create(Self.free) else {
            return nil
        }
        guard rt_atomic_u8_is_lock_free(firstState) else {
            rt_atomic_u8_destroy(firstState)
            return nil
        }
        guard let secondState = rt_atomic_u8_create(Self.free) else {
            rt_atomic_u8_destroy(firstState)
            return nil
        }
        guard rt_atomic_u8_is_lock_free(secondState) else {
            rt_atomic_u8_destroy(firstState)
            rt_atomic_u8_destroy(secondState)
            return nil
        }

        let producer = UnsafeMutablePointer<SpectrumMailboxProducerControl>
            .allocate(capacity: 1)
        producer.initialize(
            to: SpectrumMailboxProducerControl(
                accumulator: .allocate(capacity: Self.sampleCount),
                slot0: .allocate(capacity: Self.sampleCount),
                slot1: .allocate(capacity: Self.sampleCount),
                state0: firstState,
                state1: secondState,
                accumulatedCount: 0,
                nextSequence: 0,
                sequence0: 0,
                sequence1: 0
            )
        )
        self.producer = producer
    }

    var opaqueContext: UnsafeMutableRawPointer {
        UnsafeMutableRawPointer(producer)
    }

    var isLockFree: Bool {
        rt_atomic_u8_is_lock_free(producer.pointee.state0)
            && rt_atomic_u8_is_lock_free(producer.pointee.state1)
    }

    deinit {
        let control = producer.pointee
        rt_atomic_u8_destroy(control.state0)
        rt_atomic_u8_destroy(control.state1)
        control.accumulator.deallocate()
        control.slot0.deallocate()
        control.slot1.deallocate()
        producer.deinitialize(count: 1)
        producer.deallocate()
    }

    @discardableResult
    @inline(never)
    static func submit(
        context: UnsafeMutableRawPointer,
        samples: UnsafePointer<Float>,
        count: Int
    ) -> Bool {
        guard count > 0,
              count <= Int.max / MemoryLayout<Float>.stride else {
            return false
        }
        let producer = context.assumingMemoryBound(
            to: SpectrumMailboxProducerControl.self
        )
        return copyAndPublish(
            producer: producer,
            samples: samples,
            count: count
        )
    }

    func claimLatest() -> ClaimedSpectrumFrame? {
        var first: ClaimedSpectrumFrame?
        var second: ClaimedSpectrumFrame?

        if rt_atomic_u8_compare_exchange_acq_rel(
            producer.pointee.state0,
            Self.ready,
            Self.reading
        ) {
            first = ClaimedSpectrumFrame(
                slot: 0,
                sequence: producer.pointee.sequence0,
                samples: UnsafeBufferPointer(
                    start: producer.pointee.slot0,
                    count: Self.sampleCount
                )
            )
        }

        if rt_atomic_u8_compare_exchange_acq_rel(
            producer.pointee.state1,
            Self.ready,
            Self.reading
        ) {
            second = ClaimedSpectrumFrame(
                slot: 1,
                sequence: producer.pointee.sequence1,
                samples: UnsafeBufferPointer(
                    start: producer.pointee.slot1,
                    count: Self.sampleCount
                )
            )
        }

        switch (first, second) {
        case let (left?, right?):
            if Self.isNewerSequence(left.sequence, than: right.sequence) {
                release(right)
                return left
            }
            release(left)
            return right
        case let (left?, nil):
            return left
        case let (nil, right?):
            return right
        case (nil, nil):
            return nil
        }
    }

    static func isNewerSequence(_ candidate: UInt64, than reference: UInt64) -> Bool {
        Int64(bitPattern: candidate &- reference) > 0
    }

    func release(_ frame: ClaimedSpectrumFrame) {
        if frame.slot == 0 {
            rt_atomic_u8_store_release(producer.pointee.state0, Self.free)
        } else {
            rt_atomic_u8_store_release(producer.pointee.state1, Self.free)
        }
    }

    private static func copyAndPublish(
        producer: UnsafeMutablePointer<SpectrumMailboxProducerControl>,
        samples: UnsafePointer<Float>,
        count: Int
    ) -> Bool {
        var sourceOffset = 0
        var published = false

        while sourceOffset < count {
            let accumulatedCount = producer.pointee.accumulatedCount
            guard accumulatedCount >= 0,
                  accumulatedCount < Self.sampleCount,
                  sourceOffset >= 0,
                  sourceOffset < count else {
                producer.pointee.accumulatedCount = 0
                return published
            }

            let stride = MemoryLayout<Float>.stride
            let accumulatorRemaining = Self.sampleCount &- accumulatedCount
            let sourceRemaining = count &- sourceOffset
            let copyCount = accumulatorRemaining < sourceRemaining
                ? accumulatorRemaining
                : sourceRemaining
            guard copyCount > 0 else {
                producer.pointee.accumulatedCount = 0
                return published
            }
            let accumulatorByteOffset = accumulatedCount &* stride
            let sourceByteOffset = sourceOffset &* stride
            let copyByteCount = copyCount &* stride
            memcpy(
                UnsafeMutableRawPointer(producer.pointee.accumulator)
                    .advanced(by: accumulatorByteOffset),
                UnsafeRawPointer(samples).advanced(by: sourceByteOffset),
                copyByteCount
            )
            producer.pointee.accumulatedCount = accumulatedCount &+ copyCount
            sourceOffset = sourceOffset &+ copyCount

            if producer.pointee.accumulatedCount == Self.sampleCount {
                published = publishAccumulator(producer: producer) || published
                producer.pointee.accumulatedCount = 0
            }
        }

        return published
    }

    private static func publishAccumulator(
        producer: UnsafeMutablePointer<SpectrumMailboxProducerControl>
    ) -> Bool {
        // Overwrite a pending ready frame before taking a free slot.
        if rt_atomic_u8_compare_exchange_acq_rel(
            producer.pointee.state0,
            Self.ready,
            Self.writing
        ) {
            finishPublish(producer: producer, to: 0)
            return true
        }
        if rt_atomic_u8_compare_exchange_acq_rel(
            producer.pointee.state1,
            Self.ready,
            Self.writing
        ) {
            finishPublish(producer: producer, to: 1)
            return true
        }
        if rt_atomic_u8_compare_exchange_acq_rel(
            producer.pointee.state0,
            Self.free,
            Self.writing
        ) {
            finishPublish(producer: producer, to: 0)
            return true
        }
        if rt_atomic_u8_compare_exchange_acq_rel(
            producer.pointee.state1,
            Self.free,
            Self.writing
        ) {
            finishPublish(producer: producer, to: 1)
            return true
        }
        return false
    }

    private static func finishPublish(
        producer: UnsafeMutablePointer<SpectrumMailboxProducerControl>,
        to slot: Int
    ) {
        let sequence = producer.pointee.nextSequence &+ 1
        producer.pointee.nextSequence = sequence
        if slot == 0 {
            memcpy(
                producer.pointee.slot0,
                producer.pointee.accumulator,
                Self.sampleCount * MemoryLayout<Float>.stride
            )
            producer.pointee.sequence0 = sequence
            rt_atomic_u8_store_release(producer.pointee.state0, Self.ready)
        } else {
            memcpy(
                producer.pointee.slot1,
                producer.pointee.accumulator,
                Self.sampleCount * MemoryLayout<Float>.stride
            )
            producer.pointee.sequence1 = sequence
            rt_atomic_u8_store_release(producer.pointee.state1, Self.ready)
        }
    }
}
