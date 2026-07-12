import AVFoundation
import RealtimeAtomics

private func releaseRetainedSpectrumSubmissionOwner(
    _ context: UnsafeMutableRawPointer
) {
    Unmanaged<AnyObject>.fromOpaque(context).release()
}

struct NoiseEngineGraphLifecycleHooks: Sendable {
    let validateEQAccess: @MainActor @Sendable () -> Void
    let willReplaceGraph: @MainActor @Sendable () -> Void
    let didReplaceGraph: @MainActor @Sendable () -> Void

    static let none = NoiseEngineGraphLifecycleHooks(
        validateEQAccess: {},
        willReplaceGraph: {},
        didReplaceGraph: {}
    )
}

/// Owns the AVAudioEngine graph: white-noise source → 8-band EQ → output.
/// UI mutates only EQ band gains (audio-unit thread-safe); it never touches
/// the render callback.
@MainActor
public final class NoiseEngine {
    private var engine = AVAudioEngine()
    private var storedEQ: AVAudioUnitEQ
    private var eq: AVAudioUnitEQ {
        get {
            graphLifecycleHooks.validateEQAccess()
            return storedEQ
        }
        set {
            storedEQ = newValue
        }
    }
    private var bandGainState = [Float](
        repeating: 0,
        count: AudioEngineModule.bandFrequencies.count
    )
    private var globalGainState: Float = 0

    /// Explicit graph format. Built independently of the output node so the
    /// graph is valid before the audio session is active.
    let outputFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!

    public private(set) var isPlaying = false {
        didSet {
            guard oldValue != isPlaying else { return }
            onPlaybackStateChange?(isPlaying)
        }
    }

    public var onPlaybackStateChange: (@MainActor @Sendable (Bool) -> Void)?
    public var onSpectrumSnapshot:
        (@MainActor @Sendable (
            SpectrumSnapshot,
            ContinuousClock.Instant
        ) -> Void)?

    private var spectrumTapInstalled = false
    private var spectrumAnalyzer: (any SpectrumAnalyzing)?
    private var spectrumGeneration: UInt64 = 0
    private static let spectrumBufferSize = AVAudioFrameCount(
        SpectrumFFT.sampleCount
    )
    private let analyzerFactory: SpectrumAnalyzerFactory
    private let spectrumDeliverySchedule: SpectrumDeliveryGate.Scheduler
    private lazy var spectrumDeliveryGate = SpectrumDeliveryGate(
        schedule: spectrumDeliverySchedule,
        consume: { [weak self] delivery in
            self?._acceptSpectrumSnapshot(
                delivery.snapshot,
                generation: delivery.generation,
                analyzedAt: delivery.analyzedAt
            )
        }
    )
    private let notificationCenter: NotificationCenter
    private let graphLifecycleHooks: NoiseEngineGraphLifecycleHooks

    private var fadeTask: Task<Void, Never>?
    private static let fadeStepInterval: TimeInterval = 0.05

    /// True while a fade-out is actively stepping the mixer down. `fadeTask`
    /// alone isn't a reliable "fade in flight" signal — it isn't nilled on
    /// natural completion — so this flag is set/cleared explicitly around the
    /// fade's lifecycle. Internal (not private) so tests can drive it directly
    /// without spinning up real playback.
    var isFading = false

    /// Number of fade steps for a duration. Rounds (0.15/0.05 is 2.999… in
    /// double math — truncation would drop a step).
    static func fadeStepCount(for duration: TimeInterval) -> Int {
        max(1, Int((duration / fadeStepInterval).rounded()))
    }

    /// Remembers the pre-interruption playing state so `.ended` can resume correctly
    /// even though `stop()` clears `isPlaying` during `.began` handling.
    var wasPlayingBeforeInterruption = false

    /// Master output volume (0…1). Clamped; drives the main mixer. Fades ramp
    /// the mixer down but always restore to this value.
    public var masterVolume: Float = 1.0 {
        didSet {
            masterVolume = min(1, max(0, masterVolume))   // no re-entry: didSet doesn't retrigger
            // While a fade-out is in flight, the fade task owns the mixer's
            // outputVolume; writing here would zipper against its steps. The
            // fade path (finishStop) always restores the mixer to
            // masterVolume when it ends, so deferring here is safe.
            guard !isFading else { return }
            engine.mainMixerNode.outputVolume = masterVolume
        }
    }

    public var spectrumAnalysisEnabled = true {
        didSet {
            guard spectrumAnalysisEnabled != oldValue else { return }
            if spectrumAnalysisEnabled {
                if isPlaying { _installSpectrumTap() }
            } else {
                _removeSpectrumTap()
            }
        }
    }

    // MARK: - Testability seams (internal, not for production callers)

    /// Test seam: whether the most recent stop deactivated the audio session.
    private(set) var _lastStopDeactivatedSession: Bool?

    /// Test seam: current mixer volume.
    var _mixerOutputVolume: Float { engine.mainMixerNode.outputVolume }

    var isSpectrumTapInstalled: Bool { spectrumTapInstalled }
    var _spectrumGeneration: UInt64 { spectrumGeneration }

    func _setPlayingForTesting(_ value: Bool) {
        isPlaying = value
    }

    func _installSpectrumTap() {
        guard !spectrumTapInstalled,
              spectrumAnalysisEnabled,
              isPlaying else {
            return
        }

        spectrumGeneration &+= 1
        let installationGeneration = spectrumGeneration
        let sampleRate = eq.outputFormat(forBus: 0).sampleRate
        let deliveryGate = spectrumDeliveryGate
        guard let analyzer = analyzerFactory(
            sampleRate,
            installationGeneration,
            { [deliveryGate] snapshot, completedGeneration in
                deliveryGate.submit(
                    snapshot,
                    generation: completedGeneration,
                    analyzedAt: ContinuousClock().now
                )
            }
        ) else {
            return
        }

        deliveryGate.activate(generation: installationGeneration)
        let submission = analyzer.submission
        spectrumAnalyzer = analyzer
        let lifetimeContext = Unmanaged.passRetained(
            submission.owner
        ).toOpaque()
        rt_audio_node_install_spectrum_tap(
            Unmanaged.passUnretained(eq).toOpaque(),
            0,
            Self.spectrumBufferSize,
            submission.context,
            lifetimeContext,
            releaseRetainedSpectrumSubmissionOwner
        )
        spectrumTapInstalled = true
    }

    func _removeSpectrumTap() {
        guard spectrumTapInstalled || spectrumAnalyzer != nil else { return }
        spectrumDeliveryGate.deactivate()
        if spectrumTapInstalled {
            eq.removeTap(onBus: 0)
            spectrumTapInstalled = false
        }
        spectrumGeneration &+= 1
        let analyzer = spectrumAnalyzer
        spectrumAnalyzer = nil
        analyzer?.shutdown()
    }

    func _acceptSpectrumSnapshot(
        _ snapshot: SpectrumSnapshot,
        generation: UInt64,
        analyzedAt: ContinuousClock.Instant
    ) {
        guard generation == spectrumGeneration,
              isPlaying,
              spectrumAnalysisEnabled else {
            return
        }
        onSpectrumSnapshot?(snapshot, analyzedAt)
    }

    private func discardSpectrumPipelineAfterGraphLoss() {
        if spectrumTapInstalled || spectrumAnalyzer != nil {
            spectrumDeliveryGate.deactivate()
        }
        spectrumTapInstalled = false
        spectrumGeneration &+= 1
        let analyzer = spectrumAnalyzer
        spectrumAnalyzer = nil
        analyzer?.shutdown()
    }

    /// For unit tests only: inject a pre-interruption playing state without touching
    /// the live audio session.
    func _setWasPlayingBeforeInterruption(_ v: Bool) { wasPlayingBeforeInterruption = v }

    /// For unit tests only: returns true if an `.ended` interruption with the given
    /// options would trigger a resume given the current `wasPlayingBeforeInterruption`.
    func _resumeDecisionForEndedInterruption(
        options: AVAudioSession.InterruptionOptions
    ) -> Bool {
        AudioSessionPolicy.interruptionAction(type: .ended, options: options, wasPlaying: wasPlayingBeforeInterruption) == .resume
    }

    // Per-channel PRNG state, allocated once. Pointers are captured by the
    // render block so it never retains `self` or allocates on the audio thread.
    private let stateL = UnsafeMutablePointer<NoiseSource>.allocate(capacity: 1)
    private let stateR = UnsafeMutablePointer<NoiseSource>.allocate(capacity: 1)

    private static func makeEQ() -> AVAudioUnitEQ {
        let eq = AVAudioUnitEQ(numberOfBands: AudioEngineModule.bandFrequencies.count)
        for (i, f) in AudioEngineModule.bandFrequencies.enumerated() {
            let band = eq.bands[i]
            band.filterType = .parametric
            band.frequency = f
            band.bandwidth = 1.0       // ~1 octave
            band.gain = 0
            band.bypass = false
        }
        return eq
    }

    private func buildGraph() {
        let l = stateL, r = stateR
        let sourceNode = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                for (ch, buffer) in abl.enumerated() {
                    let ptr = buffer.mData!.assumingMemoryBound(to: Float.self)
                    ptr[frame] = (ch == 0) ? l.pointee.next() : r.pointee.next()
                }
            }
            return noErr
        }
        engine.attach(sourceNode)
        engine.attach(eq)
        engine.connect(sourceNode, to: eq, format: outputFormat)
        engine.connect(eq, to: engine.mainMixerNode, format: outputFormat)
        engine.mainMixerNode.outputVolume = masterVolume
    }

    public convenience init() {
        self.init(
            analyzerFactory: { sampleRate, generation, deliver in
                SpectrumAnalyzer(
                    sampleRate: sampleRate,
                    generation: generation,
                    deliver: deliver
                )
            },
            notificationCenter: .default
        )
    }

    convenience init(notificationCenter: NotificationCenter) {
        self.init(
            analyzerFactory: { sampleRate, generation, deliver in
                SpectrumAnalyzer(
                    sampleRate: sampleRate,
                    generation: generation,
                    deliver: deliver
                )
            },
            notificationCenter: notificationCenter
        )
    }

    init(
        analyzerFactory: @escaping SpectrumAnalyzerFactory,
        notificationCenter: NotificationCenter,
        graphLifecycleHooks: NoiseEngineGraphLifecycleHooks = .none,
        spectrumDeliverySchedule: @escaping SpectrumDeliveryGate.Scheduler =
            SpectrumDeliveryGate.defaultSchedule
    ) {
        self.analyzerFactory = analyzerFactory
        self.spectrumDeliverySchedule = spectrumDeliverySchedule
        self.notificationCenter = notificationCenter
        self.graphLifecycleHooks = graphLifecycleHooks
        storedEQ = Self.makeEQ()
        stateL.initialize(to: NoiseSource(seed: 0x1234_5678_9ABC_DEF0))
        stateR.initialize(to: NoiseSource(seed: 0x0FED_CBA9_8765_4321))
        buildGraph()

        notificationCenter.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(handleMediaServicesReset(_:)),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: nil
        )
    }

    isolated deinit {
        fadeTask?.cancel()
        if spectrumTapInstalled || spectrumAnalyzer != nil {
            spectrumDeliveryGate.deactivate()
        }
        if spectrumTapInstalled { eq.removeTap(onBus: 0) }
        spectrumGeneration &+= 1
        spectrumAnalyzer?.shutdown()
        engine.stop()
        notificationCenter.removeObserver(self)
        stateL.deinitialize(count: 1)
        stateL.deallocate()
        stateR.deinitialize(count: 1)
        stateR.deallocate()
    }

    public var bandCount: Int { eq.bands.count }

    public func centerFrequency(band: Int) -> Float { eq.bands[band].frequency }

    public func setGain(band: Int, dB: Float) {
        let gain = min(12, max(-24, dB))
        bandGainState[band] = gain
        eq.bands[band].gain = gain
    }

    public func gain(band: Int) -> Float { bandGainState[band] }

    /// Overall EQ output gain in dB (preset loudness makeup). Clamped ±24.
    public func setGlobalGain(_ dB: Float) {
        let gain = min(24, max(-24, dB))
        globalGainState = gain
        eq.globalGain = gain
    }

    public var globalGain: Float { globalGainState }

    public func apply(_ preset: NoisePreset) {
        for (i, g) in preset.gains.enumerated() where i < eq.bands.count {
            setGain(band: i, dB: g)
        }
        setGlobalGain(preset.makeupGain)
    }

    public func start() throws {
        fadeTask?.cancel()
        fadeTask = nil
        isFading = false
        engine.mainMixerNode.outputVolume = masterVolume
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        if !engine.isRunning { try engine.start() }
        isPlaying = true
        if spectrumAnalysisEnabled { _installSpectrumTap() }
    }

    /// `deactivateSession: false` is for interruption handling — the system has
    /// already claimed the session; deactivating it there can throw and is
    /// against AVAudioSession guidance.
    public func stop(deactivateSession: Bool = true) {
        fadeTask?.cancel()
        fadeTask = nil
        isFading = false
        _removeSpectrumTap()
        finishStop(deactivateSession: deactivateSession)
        isPlaying = false
    }

    /// Ramps the mixer to silence over `fadeDuration`, then stops the engine.
    /// `isPlaying` flips false immediately so UI reflects the stop right away.
    public func stop(fadeDuration: TimeInterval, deactivateSession: Bool = true) {
        guard fadeDuration > 0, isPlaying else {
            stop(deactivateSession: deactivateSession)
            return
        }
        fadeTask?.cancel()
        _removeSpectrumTap()
        isPlaying = false
        let steps = Self.fadeStepCount(for: fadeDuration)
        let curve = Fade.curve(
            from: engine.mainMixerNode.outputVolume,
            steps: steps
        )
        isFading = true
        fadeTask = Task { @MainActor [weak self] in
            for value in curve {
                try? await Task.sleep(for: .seconds(Self.fadeStepInterval))
                guard let self, !Task.isCancelled else { return }
                self.engine.mainMixerNode.outputVolume = value
            }
            guard let self, !Task.isCancelled else { return }
            self.isFading = false
            self.finishStop(deactivateSession: deactivateSession)
        }
    }

    private func finishStop(deactivateSession: Bool) {
        engine.stop()
        engine.mainMixerNode.outputVolume = masterVolume   // undo any partial fade
        if deactivateSession {
            try? AVAudioSession.sharedInstance().setActive(false)
        }
        _lastStopDeactivatedSession = deactivateSession
    }

    /// Applies an already-parsed interruption. Internal seam for tests.
    func _applyInterruption(type: AVAudioSession.InterruptionType,
                            options: AVAudioSession.InterruptionOptions) {
        // Capture playing state BEFORE stop() clears isPlaying on .began.
        if type == .began { wasPlayingBeforeInterruption = isPlaying }
        switch AudioSessionPolicy.interruptionAction(type: type, options: options, wasPlaying: wasPlayingBeforeInterruption) {
        case .pause:  stop(deactivateSession: false)
        case .resume: try? start()
        case .none:   break
        }
    }

    @objc nonisolated private func handleInterruption(
        _ note: Notification
    ) {
        guard let rawType = note.userInfo?[
            AVAudioSessionInterruptionTypeKey
        ] as? UInt else { return }
        let rawOptions = note.userInfo?[
            AVAudioSessionInterruptionOptionKey
        ] as? UInt ?? 0

        Task { @MainActor [weak self] in
            guard let type = AVAudioSession.InterruptionType(
                rawValue: rawType
            ) else { return }
            self?._applyInterruption(
                type: type,
                options: AVAudioSession.InterruptionOptions(
                    rawValue: rawOptions
                )
            )
        }
    }

    @objc nonisolated private func handleRouteChange(
        _ note: Notification
    ) {
        guard let rawReason = note.userInfo?[
            AVAudioSessionRouteChangeReasonKey
        ] as? UInt else { return }

        Task { @MainActor [weak self] in
            guard let reason = AVAudioSession.RouteChangeReason(
                rawValue: rawReason
            ) else { return }
            if AudioSessionPolicy.routeChangeAction(reason: reason) == .pause {
                self?.stop()
            }
        }
    }

    @objc nonisolated private func handleMediaServicesReset(
        _ note: Notification
    ) {
        Task { @MainActor [self] in
            _recoverFromMediaServicesReset()
        }
    }

    /// mediaserverd died: every node in the old graph is invalid. Rebuild from
    /// scratch, restore EQ state, resume if we were playing. Internal for tests.
    func _recoverFromMediaServicesReset() {
        let wasPlaying = isPlaying
        fadeTask?.cancel()
        fadeTask = nil
        isFading = false

        // The old graph is already invalid; do not message its EQ node.
        discardSpectrumPipelineAfterGraphLoss()
        graphLifecycleHooks.willReplaceGraph()
        engine = AVAudioEngine()
        eq = Self.makeEQ()
        graphLifecycleHooks.didReplaceGraph()
        buildGraph()
        for (index, gain) in bandGainState.enumerated() {
            eq.bands[index].gain = gain
        }
        eq.globalGain = globalGainState
        isPlaying = false
        if wasPlaying { try? start() }
    }
}
