import AVFoundation

/// Owns the AVAudioEngine graph: white-noise source → 8-band EQ → output.
/// UI mutates only EQ band gains (audio-unit thread-safe); it never touches
/// the render callback.
public final class NoiseEngine {
    private let engine = AVAudioEngine()
    private let eq: AVAudioUnitEQ

    /// Explicit graph format. Built independently of the output node so the
    /// graph is valid before the audio session is active.
    let outputFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!

    /// Whether the engine is currently producing audio. Driven by start/stop
    /// and by interruption/route handling. Observed by the UI.
    public private(set) var isPlaying = false {
        didSet {
            if oldValue != isPlaying {
                let cb = onPlaybackStateChange
                let v = isPlaying
                DispatchQueue.main.async { cb?(v) }
            }
        }
    }
    /// Fired on the main queue whenever `isPlaying` changes. Always dispatched
    /// asynchronously on the main queue, even when interrupted on a background thread.
    public var onPlaybackStateChange: ((Bool) -> Void)?

    /// Fired on the main queue with a downsampled (~128-point) mono window of
    /// recent output, for the Now Playing oscilloscope. Nil when no consumer.
    public var onScopeSamples: (([Float]) -> Void)?

    private var scopeTapInstalled = false
    private static let scopeBufferSize: AVAudioFrameCount = 4096
    private static let scopePointCount = 128

    private var fadeTask: Task<Void, Never>?
    private static let fadeStepInterval: TimeInterval = 0.05

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
            engine.mainMixerNode.outputVolume = masterVolume
        }
    }

    // MARK: - Testability seams (internal, not for production callers)

    /// Test seam: whether the most recent stop deactivated the audio session.
    private(set) var _lastStopDeactivatedSession: Bool?

    /// Test seam: current mixer volume.
    var _mixerOutputVolume: Float { engine.mainMixerNode.outputVolume }

    /// Whether the scope tap is currently installed.
    var isScopeTapInstalled: Bool { scopeTapInstalled }

    /// Installs an output tap that downsamples each buffer and delivers it on the
    /// main queue. Idempotent. Internal (called by start(); exposed for tests).
    func _installScopeTap() {
        guard !scopeTapInstalled else { return }
        eq.installTap(onBus: 0, bufferSize: Self.scopeBufferSize, format: nil) { [weak self] buffer, _ in
            guard let self, let channel = buffer.floatChannelData?[0] else { return }
            let frames = Int(buffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channel, count: frames))
            let window = downsample(samples, to: Self.scopePointCount)
            DispatchQueue.main.async { [weak self] in self?.onScopeSamples?(window) }
        }
        scopeTapInstalled = true
    }

    /// Removes the scope tap if installed. Idempotent.
    func _removeScopeTap() {
        guard scopeTapInstalled else { return }
        eq.removeTap(onBus: 0)
        scopeTapInstalled = false
    }

    /// For unit tests only: inject a pre-interruption playing state without touching
    /// the live audio session.
    func _setWasPlayingBeforeInterruption(_ v: Bool) { wasPlayingBeforeInterruption = v }

    /// For unit tests only: returns true if an `.ended` interruption with the given
    /// options would trigger a resume given the current `wasPlayingBeforeInterruption`.
    func _resumeDecisionForEndedInterruption(
        options: AVAudioSession.InterruptionOptions
    ) -> Bool {
        interruptionAction(type: .ended, options: options, wasPlaying: wasPlayingBeforeInterruption) == .resume
    }

    // Per-channel PRNG state, allocated once. Pointers are captured by the
    // render block so it never retains `self` or allocates on the audio thread.
    private let stateL = UnsafeMutablePointer<NoiseSource>.allocate(capacity: 1)
    private let stateR = UnsafeMutablePointer<NoiseSource>.allocate(capacity: 1)

    public init() {
        eq = AVAudioUnitEQ(numberOfBands: AudioEngineModule.bandFrequencies.count)
        for (i, f) in AudioEngineModule.bandFrequencies.enumerated() {
            let band = eq.bands[i]
            band.filterType = .parametric
            band.frequency = f
            band.bandwidth = 1.0       // ~1 octave
            band.gain = 0
            band.bypass = false
        }

        stateL.initialize(to: NoiseSource(seed: 0x1234_5678_9ABC_DEF0))
        stateR.initialize(to: NoiseSource(seed: 0x0FED_CBA9_8765_4321))

        let l = stateL, r = stateR
        let sourceNode = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                for (ch, buffer) in abl.enumerated() {
                    let ptr = buffer.mData!.assumingMemoryBound(to: Float.self)
                    let sample = (ch == 0) ? l.pointee.next() : r.pointee.next()
                    ptr[frame] = sample
                }
            }
            return noErr
        }

        engine.attach(sourceNode)
        engine.attach(eq)
        engine.connect(sourceNode, to: eq, format: outputFormat)
        engine.connect(eq, to: engine.mainMixerNode, format: outputFormat)

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(handleInterruption(_:)),
                       name: AVAudioSession.interruptionNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleRouteChange(_:)),
                       name: AVAudioSession.routeChangeNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stateL.deinitialize(count: 1); stateL.deallocate()
        stateR.deinitialize(count: 1); stateR.deallocate()
    }

    public var bandCount: Int { eq.bands.count }

    public func centerFrequency(band: Int) -> Float { eq.bands[band].frequency }

    public func setGain(band: Int, dB: Float) {
        eq.bands[band].gain = min(12, max(-24, dB))
    }

    public func gain(band: Int) -> Float { eq.bands[band].gain }

    /// Overall EQ output gain in dB (preset loudness makeup). Clamped ±24.
    public func setGlobalGain(_ dB: Float) {
        eq.globalGain = min(24, max(-24, dB))
    }

    public var globalGain: Float { eq.globalGain }

    public func apply(_ preset: NoisePreset) {
        for (i, g) in preset.gains.enumerated() where i < eq.bands.count {
            setGain(band: i, dB: g)
        }
        setGlobalGain(preset.makeupGain)
    }

    public func start() throws {
        fadeTask?.cancel()
        fadeTask = nil
        engine.mainMixerNode.outputVolume = masterVolume
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        if !engine.isRunning { try engine.start() }
        isPlaying = true
        _installScopeTap()
    }

    /// `deactivateSession: false` is for interruption handling — the system has
    /// already claimed the session; deactivating it there can throw and is
    /// against AVAudioSession guidance.
    public func stop(deactivateSession: Bool = true) {
        fadeTask?.cancel()
        fadeTask = nil
        _removeScopeTap()
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
        _removeScopeTap()
        isPlaying = false
        let steps = Self.fadeStepCount(for: fadeDuration)
        let curve = fadeCurve(from: engine.mainMixerNode.outputVolume, steps: steps)
        fadeTask = Task { @MainActor [weak self] in
            for v in curve {
                try? await Task.sleep(for: .seconds(Self.fadeStepInterval))
                guard let self, !Task.isCancelled else { return }
                self.engine.mainMixerNode.outputVolume = v
            }
            guard let self, !Task.isCancelled else { return }
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
        switch interruptionAction(type: type, options: options, wasPlaying: wasPlayingBeforeInterruption) {
        case .pause:  stop(deactivateSession: false)
        case .resume: try? start()
        case .none:   break
        }
    }

    @objc private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        let opts = (info[AVAudioSessionInterruptionOptionKey] as? UInt)
            .map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
        _applyInterruption(type: type, options: opts)
    }

    @objc private func handleRouteChange(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        if routeChangeAction(reason: reason) == .pause { stop() }
    }
}
