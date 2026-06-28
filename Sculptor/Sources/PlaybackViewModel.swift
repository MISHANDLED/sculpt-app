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
    /// UI-coordination flag: the custom preset (by id) that should enter inline rename.
    /// Set by SculptSheet's Save to hand off to PresetsView; cleared once consumed.
    @Published var presetToRename: UUID?
    @Published private(set) var sleepMinutes: Int?
    @Published private(set) var sleepRemaining: TimeInterval?

    let frequencies: [Float] = [60, 125, 250, 500, 1000, 2000, 4000, 8000]
    private let engine: NoiseEngine
    private var sleepDeadline: Date?
    private var sleepTask: Task<Void, Never>?

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
            stopPlayback()
            cancelSleepTimer()
        } else {
            do { try engine.start() }
            catch { errorText = error.localizedDescription }
            isPlaying = engine.isPlaying
        }
    }

    private func stopPlayback() {
        engine.stop()
        scopeSamples = []
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

    func startSleepTimer(minutes: Int) {
        sleepTask?.cancel()
        sleepMinutes = minutes
        sleepDeadline = Date().addingTimeInterval(TimeInterval(minutes * 60))
        sleepRemaining = TimeInterval(minutes * 60)
        sleepTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { break }
                self?._sleepTick()
            }
        }
    }

    func cancelSleepTimer() {
        sleepTask?.cancel()
        sleepTask = nil
        sleepDeadline = nil
        sleepMinutes = nil
        sleepRemaining = nil
    }

    /// One countdown step. Test seam: pass an explicit `now`.
    func _sleepTick(now: Date = Date()) {
        guard let deadline = sleepDeadline else { return }
        let remaining = deadline.timeIntervalSince(now)
        if remaining <= 0 {
            stopPlayback()
            cancelSleepTimer()
        } else {
            sleepRemaining = remaining
        }
    }

    func _ingestScopeSamples(_ window: [Float]) {
        guard isPlaying else { return }
        scopeSamples = window
    }
}
