import Darwin
import RealtimeAtomics

struct ClaimedSpectrumFrame: @unchecked Sendable {
    fileprivate let slot: Int
    let sequence: UInt64
    let samples: UnsafeBufferPointer<Float>
}

final class SpectrumMailbox: @unchecked Sendable {
    static let sampleCount = 4_096

    private static let free: UInt8 = 0
    private static let writing: UInt8 = 1
    private static let ready: UInt8 = 2
    private static let reading: UInt8 = 3

    private let accumulator: UnsafeMutablePointer<Float>
    private let slot0: UnsafeMutablePointer<Float>
    private let slot1: UnsafeMutablePointer<Float>
    private let state0: OpaquePointer
    private let state1: OpaquePointer

    // Producer-only fields; AVAudioNode serializes a tap callback per bus.
    private var accumulatedCount = 0
    private var nextSequence: UInt64 = 0
    private var sequence0: UInt64 = 0
    private var sequence1: UInt64 = 0

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

        state0 = firstState
        state1 = secondState
        accumulator = .allocate(capacity: Self.sampleCount)
        slot0 = .allocate(capacity: Self.sampleCount)
        slot1 = .allocate(capacity: Self.sampleCount)
    }

    var opaqueContext: UnsafeMutableRawPointer {
        Unmanaged.passUnretained(self).toOpaque()
    }

    var isLockFree: Bool {
        rt_atomic_u8_is_lock_free(state0)
            && rt_atomic_u8_is_lock_free(state1)
    }

    deinit {
        rt_atomic_u8_destroy(state0)
        rt_atomic_u8_destroy(state1)
        accumulator.deallocate()
        slot0.deallocate()
        slot1.deallocate()
    }

    @discardableResult
    static func submit(
        context: UnsafeMutableRawPointer,
        samples: UnsafePointer<Float>,
        count: Int
    ) -> Bool {
        guard count > 0 else { return false }
        let mailbox = Unmanaged<SpectrumMailbox>
            .fromOpaque(context)
            .takeUnretainedValue()
        return mailbox.copyAndPublish(samples: samples, count: count)
    }

    func claimLatest() -> ClaimedSpectrumFrame? {
        var first: ClaimedSpectrumFrame?
        var second: ClaimedSpectrumFrame?

        if rt_atomic_u8_compare_exchange_acq_rel(
            state0,
            Self.ready,
            Self.reading
        ) {
            first = ClaimedSpectrumFrame(
                slot: 0,
                sequence: sequence0,
                samples: UnsafeBufferPointer(start: slot0, count: Self.sampleCount)
            )
        }

        if rt_atomic_u8_compare_exchange_acq_rel(
            state1,
            Self.ready,
            Self.reading
        ) {
            second = ClaimedSpectrumFrame(
                slot: 1,
                sequence: sequence1,
                samples: UnsafeBufferPointer(start: slot1, count: Self.sampleCount)
            )
        }

        switch (first, second) {
        case let (left?, right?):
            if left.sequence > right.sequence {
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

    func release(_ frame: ClaimedSpectrumFrame) {
        if frame.slot == 0 {
            rt_atomic_u8_store_release(state0, Self.free)
        } else {
            rt_atomic_u8_store_release(state1, Self.free)
        }
    }

    private func copyAndPublish(
        samples: UnsafePointer<Float>,
        count: Int
    ) -> Bool {
        var sourceOffset = 0
        var published = false

        while sourceOffset < count {
            let copyCount = min(
                Self.sampleCount - accumulatedCount,
                count - sourceOffset
            )
            memcpy(
                accumulator.advanced(by: accumulatedCount),
                samples.advanced(by: sourceOffset),
                copyCount * MemoryLayout<Float>.stride
            )
            accumulatedCount += copyCount
            sourceOffset += copyCount

            if accumulatedCount == Self.sampleCount {
                published = publishAccumulator() || published
                accumulatedCount = 0
            }
        }

        return published
    }

    private func publishAccumulator() -> Bool {
        // Overwrite a pending ready frame before taking a free slot.
        if rt_atomic_u8_compare_exchange_acq_rel(
            state0,
            Self.ready,
            Self.writing
        ) {
            finishPublish(to: 0)
            return true
        }
        if rt_atomic_u8_compare_exchange_acq_rel(
            state1,
            Self.ready,
            Self.writing
        ) {
            finishPublish(to: 1)
            return true
        }
        if rt_atomic_u8_compare_exchange_acq_rel(
            state0,
            Self.free,
            Self.writing
        ) {
            finishPublish(to: 0)
            return true
        }
        if rt_atomic_u8_compare_exchange_acq_rel(
            state1,
            Self.free,
            Self.writing
        ) {
            finishPublish(to: 1)
            return true
        }
        return false
    }

    private func finishPublish(to slot: Int) {
        nextSequence &+= 1
        if slot == 0 {
            memcpy(
                slot0,
                accumulator,
                Self.sampleCount * MemoryLayout<Float>.stride
            )
            sequence0 = nextSequence
            rt_atomic_u8_store_release(state0, Self.ready)
        } else {
            memcpy(
                slot1,
                accumulator,
                Self.sampleCount * MemoryLayout<Float>.stride
            )
            sequence1 = nextSequence
            rt_atomic_u8_store_release(state1, Self.ready)
        }
    }
}
