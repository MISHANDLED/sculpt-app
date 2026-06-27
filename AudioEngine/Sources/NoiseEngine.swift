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

    /// Remembers the pre-interruption playing state so `.ended` can resume correctly
    /// even though `stop()` clears `isPlaying` during `.began` handling.
    var wasPlayingBeforeInterruption = false

    // MARK: - Testability seams (internal, not for production callers)

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

    public func apply(_ preset: NoisePreset) {
        for (i, g) in preset.gains.enumerated() where i < eq.bands.count {
            setGain(band: i, dB: g)
        }
    }

    public func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        if !engine.isRunning { try engine.start() }
        isPlaying = true
        _installScopeTap()
    }

    public func stop() {
        _removeScopeTap()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
        isPlaying = false
    }

    @objc private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        let opts = (info[AVAudioSessionInterruptionOptionKey] as? UInt)
            .map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
        // Capture playing state BEFORE stop() clears isPlaying on .began.
        if type == .began { wasPlayingBeforeInterruption = isPlaying }
        switch interruptionAction(type: type, options: opts, wasPlaying: wasPlayingBeforeInterruption) {
        case .pause:  stop()
        case .resume: try? start()
        case .none:   break
        }
    }

    @objc private func handleRouteChange(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        if routeChangeAction(reason: reason) == .pause { stop() }
    }
}
