import Foundation
import Testing
@testable import AudioEngine

enum SpectrumMailboxTestSupport {
    @discardableResult
    static func submit(
        _ values: ArraySlice<Float>,
        to mailbox: SpectrumMailbox
    ) -> Bool {
        values.withUnsafeBufferPointer { buffer in
            SpectrumMailbox.submit(
                context: mailbox.opaqueContext,
                samples: buffer.baseAddress!,
                count: buffer.count
            )
        }
    }

    static func constantWindow(_ value: Float) -> [Float] {
        [Float](repeating: value, count: SpectrumMailbox.sampleCount)
    }

    static func makeMailbox() throws -> SpectrumMailbox {
        try #require(SpectrumMailbox())
    }
}

final class SpectrumMailboxStressState: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    func markFinished() {
        lock.lock()
        finished = true
        lock.unlock()
    }

    func isFinished() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished
    }
}

@Suite("Spectrum mailbox")
struct SpectrumMailboxTests {
    @Test func platformAtomicCellsAreLockFree() throws {
        let mailbox = try SpectrumMailboxTestSupport.makeMailbox()
        #expect(mailbox.isLockFree)
    }

    @Test func arbitraryChunksAssembleOneExactWindow() throws {
        let mailbox = try SpectrumMailboxTestSupport.makeMailbox()
        let input = (0..<SpectrumMailbox.sampleCount).map(Float.init)

        #expect(!SpectrumMailboxTestSupport.submit(input[0..<997], to: mailbox))
        #expect(!SpectrumMailboxTestSupport.submit(input[997..<3_111], to: mailbox))
        #expect(SpectrumMailboxTestSupport.submit(input[3_111..<4_096], to: mailbox))

        let frame = mailbox.claimLatest()
        #expect(frame?.sequence == 1)
        #expect(frame?.samples.first == 0)
        #expect(frame?.samples.last == 4_095)
        if let frame { mailbox.release(frame) }
    }

    @Test func multiWindowSubmissionKeepsNewestAndPreservesRemainder() throws {
        let mailbox = try SpectrumMailboxTestSupport.makeMailbox()
        let input = (0..<9_000).map(Float.init)

        #expect(SpectrumMailboxTestSupport.submit(input[...], to: mailbox))
        let second = mailbox.claimLatest()
        #expect(second?.sequence == 2)
        #expect(second?.samples.first == 4_096)
        #expect(second?.samples.last == 8_191)
        if let second { mailbox.release(second) }

        let completion = [Float](repeating: -1, count: 3_288)
        #expect(SpectrumMailboxTestSupport.submit(completion[...], to: mailbox))
        let third = mailbox.claimLatest()
        #expect(third?.sequence == 3)
        #expect(third?.samples.first == 8_192)
        #expect(third?.samples[807] == 8_999)
        #expect(third?.samples[808] == -1)
        if let third { mailbox.release(third) }
    }

    @Test func readyFrameIsOverwrittenByNewerFrame() throws {
        let mailbox = try SpectrumMailboxTestSupport.makeMailbox()
        let first = SpectrumMailboxTestSupport.constantWindow(1)
        let second = SpectrumMailboxTestSupport.constantWindow(2)
        #expect(SpectrumMailboxTestSupport.submit(first[...], to: mailbox))
        #expect(SpectrumMailboxTestSupport.submit(second[...], to: mailbox))

        let frame = mailbox.claimLatest()
        #expect(frame?.sequence == 2)
        #expect(frame?.samples.allSatisfy { $0 == 2 } == true)
        if let frame { mailbox.release(frame) }
    }

    @Test func submissionDropsImmediatelyWhenBothSlotsAreReading() throws {
        let mailbox = try SpectrumMailboxTestSupport.makeMailbox()
        let firstValues = SpectrumMailboxTestSupport.constantWindow(1)
        let secondValues = SpectrumMailboxTestSupport.constantWindow(2)
        let thirdValues = SpectrumMailboxTestSupport.constantWindow(3)

        #expect(SpectrumMailboxTestSupport.submit(firstValues[...], to: mailbox))
        let first = mailbox.claimLatest()!
        #expect(SpectrumMailboxTestSupport.submit(secondValues[...], to: mailbox))
        let second = mailbox.claimLatest()!

        #expect(!SpectrumMailboxTestSupport.submit(thirdValues[...], to: mailbox))
        mailbox.release(first)
        mailbox.release(second)
    }

    @Test func producerNeverMutatesAClaimedFrame() throws {
        let mailbox = try SpectrumMailboxTestSupport.makeMailbox()
        let firstValues = SpectrumMailboxTestSupport.constantWindow(1)
        let secondValues = SpectrumMailboxTestSupport.constantWindow(2)
        let thirdValues = SpectrumMailboxTestSupport.constantWindow(3)

        #expect(SpectrumMailboxTestSupport.submit(firstValues[...], to: mailbox))
        let claimed = mailbox.claimLatest()!
        #expect(SpectrumMailboxTestSupport.submit(secondValues[...], to: mailbox))
        #expect(SpectrumMailboxTestSupport.submit(thirdValues[...], to: mailbox))
        #expect(claimed.samples.allSatisfy { $0 == 1 })
        mailbox.release(claimed)
        if let pending = mailbox.claimLatest() { mailbox.release(pending) }
    }

    @Test func concurrentProducerConsumerNeverObservesTornFrames() async throws {
        let mailbox = try SpectrumMailboxTestSupport.makeMailbox()
        let state = SpectrumMailboxStressState()

        let producer = Task.detached {
            for value in 1...2_000 {
                let window = SpectrumMailboxTestSupport.constantWindow(Float(value))
                _ = SpectrumMailboxTestSupport.submit(window[...], to: mailbox)
            }
            state.markFinished()
        }

        let consumer = Task.detached { () -> Bool in
            var torn = false
            while !state.isFinished() {
                guard let frame = mailbox.claimLatest() else { continue }
                let expected = frame.samples[0]
                if !frame.samples.allSatisfy({ $0 == expected }) { torn = true }
                mailbox.release(frame)
            }
            if let frame = mailbox.claimLatest() {
                let expected = frame.samples[0]
                if !frame.samples.allSatisfy({ $0 == expected }) { torn = true }
                mailbox.release(frame)
            }
            return torn
        }

        await producer.value
        #expect(await consumer.value == false)
    }
}
