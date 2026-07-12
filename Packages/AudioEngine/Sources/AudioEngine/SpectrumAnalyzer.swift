import Dispatch
import RealtimeAtomics

struct SpectrumSubmission: @unchecked Sendable {
    let owner: AnyObject
    let context: UnsafeMutableRawPointer
    let function: @Sendable @convention(c) (
        UnsafeMutableRawPointer,
        UnsafePointer<Float>,
        Int
    ) -> Bool

    init(
        owner: AnyObject,
        context: UnsafeMutableRawPointer,
        function: @escaping @Sendable @convention(c) (
            UnsafeMutableRawPointer,
            UnsafePointer<Float>,
            Int
        ) -> Bool
    ) {
        self.owner = owner
        self.context = context
        self.function = function
    }

    @discardableResult
    func submit(
        _ samples: UnsafePointer<Float>,
        count: Int
    ) -> Bool {
        function(context, samples, count)
    }
}

protocol SpectrumAnalyzing: AnyObject {
    var submission: SpectrumSubmission { get }
    func shutdown()
}

typealias SpectrumAnalyzerFactory = @MainActor (
    Double,
    UInt64,
    @escaping @Sendable (SpectrumSnapshot, UInt64) -> Void
) -> (any SpectrumAnalyzing)?

final class SpectrumAnalyzer: SpectrumAnalyzing, @unchecked Sendable {
    let submission: SpectrumSubmission

    private let generation: UInt64
    private let deliver: @Sendable (SpectrumSnapshot, UInt64) -> Void
    private let mailbox: SpectrumMailbox
    private let fft: SpectrumFFT
    private let queue: DispatchQueue
    private let queueKey: DispatchSpecificKey<UInt8>
    private let timer: DispatchSourceTimer
    private let stopped: OpaquePointer
    private let beforeShutdownJoin: (@Sendable () -> Void)?

    convenience init?(
        sampleRate: Double,
        generation: UInt64,
        deliver: @escaping @Sendable (SpectrumSnapshot, UInt64) -> Void
    ) {
        self.init(
            sampleRate: sampleRate,
            generation: generation,
            pollInterval: .nanoseconds(16_666_667),
            deliver: deliver
        )
    }

    init?(
        sampleRate: Double,
        generation: UInt64,
        pollInterval: DispatchTimeInterval,
        beforeShutdownJoin: (@Sendable () -> Void)? = nil,
        deliver: @escaping @Sendable (SpectrumSnapshot, UInt64) -> Void
    ) {
        guard let fft = SpectrumFFT(sampleRate: sampleRate),
              let stopped = rt_atomic_u8_create(0) else {
            return nil
        }
        guard rt_atomic_u8_is_lock_free(stopped) else {
            rt_atomic_u8_destroy(stopped)
            return nil
        }
        guard let mailbox = SpectrumMailbox() else {
            rt_atomic_u8_destroy(stopped)
            return nil
        }
        let queue = DispatchQueue(
            label: "com.mishandled.sculptor.spectrum-analysis",
            qos: .utility
        )
        let queueKey = DispatchSpecificKey<UInt8>()
        queue.setSpecific(key: queueKey, value: 1)
        let timer = DispatchSource.makeTimerSource(queue: queue)

        self.fft = fft
        self.mailbox = mailbox
        self.queue = queue
        self.queueKey = queueKey
        self.timer = timer
        self.generation = generation
        self.deliver = deliver
        self.stopped = stopped
        self.beforeShutdownJoin = beforeShutdownJoin
        submission = SpectrumSubmission(
            owner: mailbox,
            context: mailbox.opaqueContext,
            function: { context, samples, count in
                SpectrumMailbox.submit(
                    context: context,
                    samples: samples,
                    count: count
                )
            }
        )

        timer.setEventHandler { [weak self] in
            self?.pollLatestFrame()
        }
        timer.schedule(
            deadline: .now() + pollInterval,
            repeating: pollInterval,
            leeway: .milliseconds(2)
        )
        timer.activate()
    }

    deinit {
        shutdown()
        rt_atomic_u8_destroy(stopped)
    }

    func shutdown() {
        let wasStopped = rt_atomic_u8_exchange_acq_rel(stopped, 1)
        if wasStopped == 0 {
            timer.cancel()
        }
        guard DispatchQueue.getSpecific(key: queueKey) == nil else {
            return
        }
        beforeShutdownJoin?()
        queue.sync {}
    }

    private func pollLatestFrame() {
        guard rt_atomic_u8_load_acquire(stopped) == 0,
              let frame = mailbox.claimLatest() else {
            return
        }
        let snapshot = fft.analyze(frame.samples)
        mailbox.release(frame)
        guard rt_atomic_u8_load_acquire(stopped) == 0 else { return }
        deliver(snapshot, generation)
    }
}
