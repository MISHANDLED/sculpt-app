import SwiftUI
import AudioEngine
import Foundation

enum PresetSelection: Equatable {
    case none
    case builtin(NoisePreset)
    case custom(UUID)
}

@MainActor
final class PlaybackViewModel: ObservableObject {
    @Published var gains: [Float]
    @Published private(set) var isPlaying = false
    @Published private(set) var selection: PresetSelection = .none
    @Published private(set) var scopeSamples: [Float] = []
    @Published var errorText: String?

    let frequencies: [Float] = [60, 125, 250, 500, 1000, 2000, 4000, 8000]
    private let engine: NoiseEngine

    init(engine: NoiseEngine = NoiseEngine()) {
        self.engine = engine
        gains = [Float](repeating: 0, count: 8)
        engine.onPlaybackStateChange = { [weak self] playing in
            Task { @MainActor in self?.isPlaying = playing }
        }
        engine.onScopeSamples = { [weak self] window in
            Task { @MainActor in self?._ingestScopeSamples(window) }
        }
    }

    func togglePlay() {
        if isPlaying {
            engine.stop()
            scopeSamples = []
        } else {
            do { try engine.start() }
            catch { errorText = error.localizedDescription }
        }
        isPlaying = engine.isPlaying
    }

    func setGain(band: Int, dB: Float) {
        gains[band] = dB
        engine.setGain(band: band, dB: dB)
        selection = .none
    }

    func select(_ preset: NoisePreset) {
        engine.apply(preset)
        gains = preset.gains
        selection = .builtin(preset)
    }

    /// Applies an explicit gain set (a saved custom preset) and marks it active.
    func applyCustom(id: UUID, gains newGains: [Float]) {
        for (i, g) in newGains.enumerated() where i < frequencies.count {
            engine.setGain(band: i, dB: g)
        }
        gains = newGains
        selection = .custom(id)
    }

    /// Updates the published scope window. Internal seam for the engine callback and tests.
    func _ingestScopeSamples(_ window: [Float]) {
        guard isPlaying else { return }
        scopeSamples = window
    }
}
