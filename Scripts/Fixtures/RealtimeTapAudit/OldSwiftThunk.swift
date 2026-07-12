import AVFAudio

@_silgen_name("rt_audio_node_install_spectrum_tap")
private func referenceTapInstaller()

@inline(never)
public func installFixtureTap() {
    referenceTapInstaller()
}

@inline(never)
public func alternateTapEntry(
    _ buffer: AVAudioPCMBuffer,
    at time: AVAudioTime
) {
    _ = buffer.frameLength
    _ = time.sampleTime
}
