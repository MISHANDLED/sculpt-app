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
    @Published private(set) var spectrumSnapshot = SpectrumSnapshot.zero
    @Published private(set) var spectrumReceivedAt: ContinuousClock.Instant?
    @Published private(set) var visualizationActive = false
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
    private var startTask: Task<Void, Never>?
    private var startRequestID: UInt64 = 0
    private var nowPlaying: NowPlayingService?

    private static let kSelection = "sculptor.lastSelection"
    private static let kGains = "sculptor.lastGains"
    private static let kVolume = "sculptor.masterVolume"

    convenience init(defaults: UserDefaults = .standard) {
        self.init(engine: NoiseEngine(), defaults: defaults)
    }

    init(engine: NoiseEngine, defaults: UserDefaults = .standard) {
        self.engine = engine
        self.defaults = defaults
        gains = [Float](repeating: 0, count: 8)
        engine.spectrumAnalysisEnabled = false
        engine.onPlaybackStateChange = { [weak self] playing in
            self?._applyPlaybackState(playing)
        }
        engine.onSpectrumSnapshot = { [weak self] snapshot, analyzedAt in
            guard let self else { return }
            self._ingestSpectrumSnapshot(snapshot, at: analyzedAt)
        }
        let storedVolume = (defaults.object(forKey: Self.kVolume) as? Double).map(Float.init) ?? 1.0
        masterVolume = storedVolume
        engine.masterVolume = storedVolume
        restoreLastSelection()

        nowPlaying = NowPlayingService(
            onPlay: { [weak self] in
                Task { @MainActor in
                    self?._handleRemotePlay()
                }
            },
            onPause: { [weak self] in
                Task { @MainActor in
                    self?._handleRemotePause()
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
        if hasEffectivePlaybackIntent {
            stopPlayback()
            cancelSleepTimer()
        } else {
            beginPlaybackRequest()
        }
    }

    private func stopPlayback(fade: TimeInterval = 0.15) {
        startRequestID += 1
        let pendingStart = startTask
        startTask = nil
        pendingStart?.cancel()
        engine.stop(fadeDuration: fade)
        _applyPlaybackState(engine.isPlaying)
    }

    private var hasEffectivePlaybackIntent: Bool {
        isPlaying || startTask != nil || engine.isPlaybackRequested
    }

    private func beginPlaybackRequest() {
        errorText = nil
        startRequestID += 1
        let requestID = startRequestID
        startTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try Task.checkCancellation()
                try await engine.start()
                try Task.checkCancellation()
                guard requestID == startRequestID else { return }
                startTask = nil
                _applyPlaybackState(engine.isPlaying)
            } catch is CancellationError {
                guard requestID == startRequestID else { return }
                startTask = nil
                _applyPlaybackState(engine.isPlaying)
            } catch {
                guard requestID == startRequestID else { return }
                startTask = nil
                errorText = error.localizedDescription
                _applyPlaybackState(engine.isPlaying)
            }
        }
    }

    func _handleRemotePlay() {
        guard !hasEffectivePlaybackIntent else { return }
        beginPlaybackRequest()
    }

    func _handleRemotePause() {
        guard hasEffectivePlaybackIntent else { return }
        stopPlayback()
        cancelSleepTimer()
    }

    func setGain(band: Int, dB: Float) {
        gains[band] = dB
        engine.setGain(band: band, dB: dB)
        // Builtin selections carry an energy makeup gain, so recompute it from
        // the live gains — otherwise sculpting a band up leaves a stale
        // (too-hot) makeup in place and can clip. Custom/none selections live
        // at globalGain 0 (no canonical loudness reference; user set them by
        // ear) — recomputing there would turn a sub-dB nudge on a quiet
        // profile into a clamped +12 dB loudness jump, and would diverge from
        // restoreLastSelection, which restores them at 0.
        if case .builtin = selection {
            engine.setGlobalGain(NoisePreset.makeupGain(for: gains))
        } else {
            engine.setGlobalGain(0)
        }
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
        // Custom presets have no canonical loudness reference — the user set
        // these gains by ear at globalGain 0, so re-normalizing here would
        // change what they saved. (A later setGain edit will still recompute
        // live makeup, same as for builtins.)
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
              let sel = SelectionPersistence.parse(token),
              let stored = defaults.array(forKey: Self.kGains) as? [Double],
              stored.count == frequencies.count else { return }
        let restored = stored.map { Float($0) }
        for (i, g) in restored.enumerated() { engine.setGain(band: i, dB: g) }
        gains = restored
        selection = sel
        // Makeup is computed from the gains actually being restored (which may
        // be user-edited), not the preset's canonical table — an unedited
        // restore yields the same gains as the preset, so this is equivalent
        // in that case and correct in the edited case.
        if case .builtin = sel {
            engine.setGlobalGain(NoisePreset.makeupGain(for: restored))
        } else {
            engine.setGlobalGain(0)
        }
    }

    private func persistSelection() {
        if let token = SelectionPersistence.token(selection) {
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

    func _applyPlaybackState(_ playing: Bool) {
        if isPlaying != playing {
            isPlaying = playing
        }
        if !playing { clearSpectrumTarget() }
    }

    func _ingestSpectrumSnapshot(
        _ snapshot: SpectrumSnapshot,
        at instant: ContinuousClock.Instant
    ) {
        guard isPlaying, visualizationActive else { return }
        spectrumSnapshot = snapshot
        spectrumReceivedAt = instant
    }

    func setVisualizationActive(_ active: Bool) {
        visualizationActive = active
        engine.spectrumAnalysisEnabled = active
        if !active { clearSpectrumTarget() }
    }

    private func clearSpectrumTarget() {
        spectrumSnapshot = .zero
        spectrumReceivedAt = nil
    }
}
