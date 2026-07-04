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
    @Published private(set) var isPlaying = false {
        didSet { if oldValue != isPlaying { pushNowPlaying() } }
    }
    @Published private(set) var selection: PresetSelection = .none
    @Published private(set) var isEdited = false
    @Published private(set) var scopeSamples: [Float] = []
    @Published var errorText: String?
    /// UI-coordination flag: the custom preset (by id) that should enter inline rename.
    /// Set by SculptSheet's Save to hand off to PresetsView; cleared once consumed.
    @Published var presetToRename: UUID?
    @Published private(set) var sleepMinutes: Int?
    @Published private(set) var sleepRemaining: TimeInterval?
    @Published var masterVolume: Float = 1.0 {
        didSet {
            engine.masterVolume = masterVolume
            defaults.set(Double(masterVolume), forKey: Self.kVolume)
        }
    }

    /// Resolved display title (HomeView pushes it — custom preset names need @Query).
    @Published var nowPlayingTitle = "Custom" {
        didSet { if oldValue != nowPlayingTitle { pushNowPlaying() } }
    }

    let frequencies: [Float] = [60, 125, 250, 500, 1000, 2000, 4000, 8000]
    private let engine: NoiseEngine
    private let defaults: UserDefaults
    private var sleepDeadline: Date?
    private var sleepTask: Task<Void, Never>?
    private var nowPlaying: NowPlayingService?

    private static let kSelection = "sculptor.lastSelection"
    private static let kGains = "sculptor.lastGains"
    private static let kVolume = "sculptor.masterVolume"

    init(engine: NoiseEngine = NoiseEngine(), defaults: UserDefaults = .standard) {
        self.engine = engine
        self.defaults = defaults
        gains = [Float](repeating: 0, count: 8)
        engine.onPlaybackStateChange = { [weak self] playing in
            Task { @MainActor in self?.isPlaying = playing }
        }
        engine.onScopeSamples = { [weak self] window in
            Task { @MainActor in self?._ingestScopeSamples(window) }
        }
        let storedVolume = (defaults.object(forKey: Self.kVolume) as? Double).map(Float.init) ?? 1.0
        masterVolume = storedVolume
        engine.masterVolume = storedVolume
        restoreLastSelection()

        nowPlaying = NowPlayingService(
            onPlay: { [weak self] in
                Task { @MainActor in
                    guard let self, !self.isPlaying else { return }
                    self.togglePlay()
                }
            },
            onPause: { [weak self] in
                Task { @MainActor in
                    guard let self, self.isPlaying else { return }
                    self.togglePlay()
                }
            },
            onToggle: { [weak self] in
                Task { @MainActor in self?.togglePlay() }
            }
        )
        pushNowPlaying()
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
            errorText = nil
            do { try engine.start() }
            catch { errorText = error.localizedDescription }
            isPlaying = engine.isPlaying
        }
    }

    private func stopPlayback(fade: TimeInterval = 0.15) {
        engine.stop(fadeDuration: fade)
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
        persistSelection()
    }

    func applyCustom(id: UUID, gains newGains: [Float]) {
        guard newGains.count == frequencies.count else { return }
        for (i, g) in newGains.enumerated() {
            engine.setGain(band: i, dB: g)
        }
        engine.setGlobalGain(0)
        gains = newGains
        selection = .custom(id)
        isEdited = false
        persistSelection()
    }

    func reset() {
        for i in 0..<frequencies.count {
            gains[i] = 0
            engine.setGain(band: i, dB: 0)
        }
        engine.setGlobalGain(0)
        selection = .none
        isEdited = false
        persistSelection()
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
            cancelSleepTimer()
            stopPlayback(fade: 10)
        } else {
            sleepRemaining = remaining
        }
    }

    private func restoreLastSelection() {
        guard let token = defaults.string(forKey: Self.kSelection),
              let sel = parseSelectionToken(token),
              let stored = defaults.array(forKey: Self.kGains) as? [Double],
              stored.count == frequencies.count else { return }
        let restored = stored.map { Float($0) }
        for (i, g) in restored.enumerated() { engine.setGain(band: i, dB: g) }
        gains = restored
        selection = sel
        if case .builtin(let preset) = sel {
            engine.setGlobalGain(preset.makeupGain)
        } else {
            engine.setGlobalGain(0)
        }
    }

    private func persistSelection() {
        if let token = selectionToken(selection) {
            defaults.set(token, forKey: Self.kSelection)
            defaults.set(gains.map { Double($0) }, forKey: Self.kGains)
        } else {
            defaults.removeObject(forKey: Self.kSelection)
            defaults.removeObject(forKey: Self.kGains)
        }
    }

    private func pushNowPlaying() {
        nowPlaying?.update(title: nowPlayingTitle, isPlaying: isPlaying)
    }

    func _ingestScopeSamples(_ window: [Float]) {
        guard isPlaying else { return }
        scopeSamples = window
    }

    /// Scene-phase hook: tear the scope tap down in background, restore in foreground.
    func setScopeActive(_ active: Bool) {
        engine.scopeEnabled = active
        if !active { scopeSamples = [] }
    }
}
