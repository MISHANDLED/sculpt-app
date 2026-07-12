import AVFoundation
import Foundation
import Testing
@testable import AudioEngine

@MainActor
@Suite("Media services reset recovery")
struct NoiseEngineMediaResetTests {
    @Test func rebuildPreservesGainsGlobalAndBandCount() {
        let engine = NoiseEngine()
        engine.setGain(band: 2, dB: 5)
        engine.setGlobalGain(3)
        engine._recoverFromMediaServicesReset()
        #expect(engine.bandCount == 8)
        #expect(engine.gain(band: 2) == 5)
        #expect(abs(engine.globalGain - 3) < 0.001)
        #expect(!engine.isPlaying)
    }

    @Test func rebuildInvalidatesAnalyzerAndUsesRebuiltFormat() {
        let spy = SpectrumAnalyzerFactorySpy()
        let engine = NoiseEngine(
            analyzerFactory: spy.factory,
            notificationCenter: NotificationCenter()
        )
        engine._setPlayingForTesting(true)
        engine._installSpectrumTap()
        let firstGeneration = engine._spectrumGeneration
        engine._setPlayingForTesting(false)

        engine._recoverFromMediaServicesReset()
        #expect(!engine.isSpectrumTapInstalled)
        #expect(spy.analyzers[0].shutdownCount == 1)

        engine._setPlayingForTesting(true)
        engine._installSpectrumTap()
        #expect(engine._spectrumGeneration > firstGeneration)
        #expect(spy.sampleRates == [44_100, 44_100])
        engine._removeSpectrumTap()
    }

    @Test func resetNotificationHopsToMainActor() async {
        let center = NotificationCenter()
        let engine = NoiseEngine(notificationCenter: center)
        engine.isFading = true

        await Task.detached {
            center.post(
                name: AVAudioSession.mediaServicesWereResetNotification,
                object: nil
            )
        }.value
        for _ in 0..<20 where engine.isFading { await Task.yield() }
        #expect(!engine.isFading)
    }
}
