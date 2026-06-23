import SwiftUI
import AudioEngine

@MainActor
final class SpikeViewModel: ObservableObject {
    @Published var isPlaying = false
    @Published var gains: [Float]
    @Published var errorText: String?

    let frequencies: [Float] = [60, 125, 250, 500, 1000, 2000, 4000, 8000]
    private let engine = NoiseEngine()

    init() {
        gains = [Float](repeating: 0, count: 8)
    }

    func togglePlay() {
        if isPlaying {
            engine.stop()
            isPlaying = false
        } else {
            do { try engine.start(); isPlaying = true }
            catch { errorText = error.localizedDescription }
        }
    }

    func setGain(band: Int, dB: Float) {
        gains[band] = dB
        engine.setGain(band: band, dB: dB)
    }

    func apply(_ preset: NoisePreset) {
        engine.apply(preset)
        gains = preset.gains
    }
}
