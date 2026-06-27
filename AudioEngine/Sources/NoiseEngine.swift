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
    }

    deinit {
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
    }

    public func stop() {
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}
