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
    @Published private(set) var isEdited = false
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

    /// Display name for the active selection. Returns "" for .custom — caller resolves via @Query.
    var presetDisplayName: String {
        switch selection {
        case .builtin(let p):
            switch p {
            case .white:         return "White"
            case .pink:          return "Pink"
            case .brown:         return "Brown"
            case .grey:          return "Grey"
            case .speechBlocker: return "Speech blocker"
            }
        case .custom:   return ""
        case .none:     return "Custom"
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
        isEdited = true
        // selection preserved — home header keeps showing the preset name with EDITED badge
    }

    func select(_ preset: NoisePreset) {
        engine.apply(preset)
        gains = preset.gains
        selection = .builtin(preset)
        isEdited = false
    }

    func applyCustom(id: UUID, gains newGains: [Float]) {
        guard newGains.count == frequencies.count else { return }
        for (i, g) in newGains.enumerated() {
            engine.setGain(band: i, dB: g)
        }
        gains = newGains
        selection = .custom(id)
        isEdited = false
    }

    func reset() {
        for i in 0..<frequencies.count {
            gains[i] = 0
            engine.setGain(band: i, dB: 0)
        }
        selection = .none
        isEdited = false
    }

    func _ingestScopeSamples(_ window: [Float]) {
        guard isPlaying else { return }
        scopeSamples = window
    }
}
