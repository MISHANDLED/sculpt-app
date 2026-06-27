import Testing
import AVFoundation
@testable import AudioEngine

@Test func usesExplicitStereo44kFormat() {
    let engine = NoiseEngine()
    #expect(engine.outputFormat.sampleRate == 44100)
    #expect(engine.outputFormat.channelCount == 2)
    #expect(engine.outputFormat.commonFormat == .pcmFormatFloat32)
}
