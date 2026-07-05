# Audio/UX Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Sculptor work as a real sleep/focus app: audio survives lock screen, lock-screen controls, overnight robustness (media-services reset, battery), fade-outs, equal-loudness presets, master volume.

**Architecture:** All audio-graph work stays in the `AudioEngine` framework (no MediaPlayer/SwiftUI there). Lock-screen integration (`NowPlayingService`, MediaPlayer) lives in the `Sculptor` app target, wired through `PlaybackViewModel`. UI changes limited to `HomeView` (volume slider) and `RootView` (scenePhase).

**Tech Stack:** Swift 5.9+, SwiftUI, AVFoundation, MediaPlayer, Swift Testing (`@Test`/`#expect`), Tuist, iOS 17.

## Global Constraints

- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`) — NOT XCTest.
- Full-suite test command (run from repo root; output MUST redirect to a log file — piping to grep makes runs look hung):
  `xcodebuild test -workspace Sculptor.xcworkspace -scheme Sculptor-Workspace -destination 'platform=iOS Simulator,name=iPhone Air' > /tmp/sculptor-tests.log 2>&1; echo "exit=$?"; tail -20 /tmp/sculptor-tests.log`
  Exit 0 + "** TEST SUCCEEDED **" in log = green. ALWAYS run full scheme before trusting green (tests run parallel; isolation masks interactions).
- Commits on `master` (trunk, no branches — project convention) using:
  `git -c user.name='Sculptor' -c user.email='dev@sculptor.local' commit -m "..."`
- After ANY `Project.swift` change run `tuist generate --no-open` before building.
- `NoiseEngine` render callback must never allocate or retain `self`.
- Never call `engine.start()`/`AVAudioSession.setActive(true)` inside unit tests — tests construct engines but don't start audio (project norm).
- SourceKit false positives ("No such module 'Testing'", "AVAudioSession unavailable") are editor-only noise; `xcodebuild` is ground truth.
- Existing suite: 27+ tests green. Keep them green.

---

### Task 1: Background audio mode + session-deactivation split

**Files:**
- Modify: `Project.swift` (~line 49, Sculptor app target `infoPlist`)
- Modify: `AudioEngine/Sources/NoiseEngine.swift` (`stop()`, `handleInterruption`)
- Test: `AudioEngine/Tests/NoiseEngineSessionTests.swift` (create)

**Interfaces:**
- Produces: `NoiseEngine.stop(deactivateSession: Bool = true)`; internal seam `_applyInterruption(type:options:)`; internal `private(set) var _lastStopDeactivatedSession: Bool?`. Later tasks call `stop(deactivateSession:)`.

- [ ] **Step 1: Write failing test**

Create `AudioEngine/Tests/NoiseEngineSessionTests.swift`:

```swift
import Testing
import AVFoundation
@testable import AudioEngine

@Suite("Session deactivation policy")
struct NoiseEngineSessionTests {

    @Test func manualStopDeactivatesSession() {
        let engine = NoiseEngine()
        engine.stop()
        #expect(engine._lastStopDeactivatedSession == true)
    }

    @Test func interruptionStopKeepsSessionActive() {
        let engine = NoiseEngine()
        engine._applyInterruption(type: .began, options: [])
        #expect(engine._lastStopDeactivatedSession == false)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -workspace Sculptor.xcworkspace -scheme AudioEngine -destination 'platform=iOS Simulator,name=iPhone Air' > /tmp/ae-tests.log 2>&1; echo "exit=$?"; tail -20 /tmp/ae-tests.log`
Expected: BUILD FAILURE — `_lastStopDeactivatedSession`/`_applyInterruption` undefined.

- [ ] **Step 3: Implement in NoiseEngine.swift**

Replace the existing `stop()`:

```swift
    /// Test seam: whether the most recent stop deactivated the audio session.
    private(set) var _lastStopDeactivatedSession: Bool?

    /// `deactivateSession: false` is for interruption handling — the system has
    /// already claimed the session; deactivating it there can throw and is
    /// against AVAudioSession guidance.
    public func stop(deactivateSession: Bool = true) {
        _removeScopeTap()
        engine.stop()
        if deactivateSession {
            try? AVAudioSession.sharedInstance().setActive(false)
        }
        _lastStopDeactivatedSession = deactivateSession
        isPlaying = false
    }
```

Replace `handleInterruption` with a parse wrapper + testable core:

```swift
    /// Applies an already-parsed interruption. Internal seam for tests.
    func _applyInterruption(type: AVAudioSession.InterruptionType,
                            options: AVAudioSession.InterruptionOptions) {
        // Capture playing state BEFORE stop() clears isPlaying on .began.
        if type == .began { wasPlayingBeforeInterruption = isPlaying }
        switch interruptionAction(type: type, options: options, wasPlaying: wasPlayingBeforeInterruption) {
        case .pause:  stop(deactivateSession: false)
        case .resume: try? start()
        case .none:   break
        }
    }

    @objc private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        let opts = (info[AVAudioSessionInterruptionOptionKey] as? UInt)
            .map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
        _applyInterruption(type: type, options: opts)
    }
```

- [ ] **Step 4: Add background audio mode to Project.swift**

In the `Sculptor` app target, change:

```swift
            infoPlist: .extendingDefault(with: [
                "UILaunchScreen": [:]
            ]),
```

to:

```swift
            infoPlist: .extendingDefault(with: [
                "UILaunchScreen": [:],
                "UIBackgroundModes": ["audio"]
            ]),
```

- [ ] **Step 5: Regenerate and verify plist**

Run: `tuist generate --no-open && rg -l "UIBackgroundModes" Derived`
Expected: at least one generated Info.plist path printed (e.g. `Derived/InfoPlists/Sculptor-Info.plist`).

- [ ] **Step 6: Run AudioEngine tests to verify pass**

Run: `xcodebuild test -workspace Sculptor.xcworkspace -scheme AudioEngine -destination 'platform=iOS Simulator,name=iPhone Air' > /tmp/ae-tests.log 2>&1; echo "exit=$?"; tail -20 /tmp/ae-tests.log`
Expected: exit=0, `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add Project.swift AudioEngine/Sources/NoiseEngine.swift AudioEngine/Tests/NoiseEngineSessionTests.swift
git -c user.name='Sculptor' -c user.email='dev@sculptor.local' commit -m "feat: background audio mode; keep session active through interruptions"
```

---

### Task 2: Master volume (engine + persistence + Home slider)

**Files:**
- Modify: `AudioEngine/Sources/NoiseEngine.swift`
- Modify: `Sculptor/Sources/PlaybackViewModel.swift`
- Modify: `Sculptor/Sources/HomeView.swift` (`heroCenter`)
- Test: `AudioEngine/Tests/NoiseEngineTests.swift` (append), `Sculptor/Tests/PlaybackViewModelTests.swift` (append)

**Interfaces:**
- Produces: `NoiseEngine.masterVolume: Float` (0…1, clamped, drives `mainMixerNode.outputVolume`); seam `_mixerOutputVolume: Float { get }`; `PlaybackViewModel.masterVolume: Float` (`@Published`, persisted under `"sculptor.masterVolume"`). Task 3's fade restores to `masterVolume`.

- [ ] **Step 1: Write failing tests**

Append to `AudioEngine/Tests/NoiseEngineTests.swift`:

```swift
@Test func masterVolumeClampsAndDrivesMixer() {
    let engine = NoiseEngine()
    engine.masterVolume = 1.5
    #expect(engine.masterVolume == 1.0)
    engine.masterVolume = -0.2
    #expect(engine.masterVolume == 0.0)
    engine.masterVolume = 0.6
    #expect(abs(engine._mixerOutputVolume - 0.6) < 0.001)
}
```

Append inside `PlaybackViewModelTests` suite:

```swift
    @Test func masterVolumeDefaultsToFullAndPersists() {
        let d = freshDefaults()
        let vm = PlaybackViewModel(defaults: d)
        #expect(vm.masterVolume == 1.0)
        vm.masterVolume = 0.4
        let vm2 = PlaybackViewModel(defaults: d)
        #expect(abs(vm2.masterVolume - 0.4) < 0.001)
    }
```

- [ ] **Step 2: Run to verify failure**

Full suite command from Global Constraints. Expected: BUILD FAILURE — `masterVolume` undefined.

- [ ] **Step 3: Implement engine side (NoiseEngine.swift)**

```swift
    /// Master output volume (0…1). Clamped; drives the main mixer. Fades ramp
    /// the mixer down but always restore to this value.
    public var masterVolume: Float = 1.0 {
        didSet {
            masterVolume = min(1, max(0, masterVolume))   // no re-entry: didSet doesn't retrigger
            engine.mainMixerNode.outputVolume = masterVolume
        }
    }

    /// Test seam: current mixer volume.
    var _mixerOutputVolume: Float { engine.mainMixerNode.outputVolume }
```

- [ ] **Step 4: Implement VM side (PlaybackViewModel.swift)**

Add key constant next to the others:

```swift
    private static let kVolume = "sculptor.masterVolume"
```

Add published property (after `sleepRemaining`):

```swift
    @Published var masterVolume: Float = 1.0 {
        didSet {
            engine.masterVolume = masterVolume
            defaults.set(Double(masterVolume), forKey: Self.kVolume)
        }
    }
```

In `init`, after `gains = [Float](repeating: 0, count: 8)` (property observers don't fire during init, so push to engine explicitly):

```swift
        let storedVolume = (defaults.object(forKey: Self.kVolume) as? Double).map(Float.init) ?? 1.0
        masterVolume = storedVolume
        engine.masterVolume = storedVolume
```

- [ ] **Step 5: Add slider to HomeView `heroCenter`**

Insert between `ScopeVisualizer(...)` block and the `Text(vm.isPlaying ...)` line:

```swift
            HStack(spacing: DockSpacing.sm) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(DockColor.textTertiary)
                Slider(value: $vm.masterVolume, in: 0...1)
                    .tint(DockColor.accent)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(DockColor.textTertiary)
            }
            .padding(.horizontal, DockSpacing.xl * 1.5)
```

- [ ] **Step 6: Run full suite to verify pass**

Full suite command. Expected: exit=0, `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add AudioEngine/Sources/NoiseEngine.swift AudioEngine/Tests/NoiseEngineTests.swift Sculptor/Sources/PlaybackViewModel.swift Sculptor/Tests/PlaybackViewModelTests.swift Sculptor/Sources/HomeView.swift
git -c user.name='Sculptor' -c user.email='dev@sculptor.local' commit -m "feat: master volume with persistence and Home slider"
```

---

### Task 3: Fade-out on stop + sleep-timer fade + stale error clearing

**Files:**
- Create: `AudioEngine/Sources/Fade.swift`
- Modify: `AudioEngine/Sources/NoiseEngine.swift` (`start()`, `stop(deactivateSession:)`, new `stop(fadeDuration:deactivateSession:)`)
- Modify: `Sculptor/Sources/PlaybackViewModel.swift` (`togglePlay`, `stopPlayback`, `_sleepTick`)
- Test: `AudioEngine/Tests/FadeTests.swift` (create)

**Interfaces:**
- Consumes: `masterVolume` from Task 2; `stop(deactivateSession:)` + `_lastStopDeactivatedSession` from Task 1.
- Produces: `func fadeCurve(from start: Float, steps: Int) -> [Float]` (internal, AudioEngine); `NoiseEngine.stop(fadeDuration: TimeInterval, deactivateSession: Bool = true)` — flips `isPlaying` false immediately, ramps mixer to 0, then stops and restores `masterVolume`.

- [ ] **Step 1: Write failing tests**

Create `AudioEngine/Tests/FadeTests.swift`:

```swift
import Testing
@testable import AudioEngine

@Suite("Fade curve")
struct FadeTests {

    @Test func linearRampToExactZero() {
        #expect(fadeCurve(from: 1, steps: 4) == [0.75, 0.5, 0.25, 0])
    }

    @Test func emptyForNonPositiveSteps() {
        #expect(fadeCurve(from: 1, steps: 0).isEmpty)
        #expect(fadeCurve(from: 1, steps: -3).isEmpty)
    }

    @Test func lastElementAlwaysZero() {
        #expect(fadeCurve(from: 0.6, steps: 7).last == 0)
    }

    @Test func fadeStopFallsBackToImmediateWhenNotPlaying() {
        let engine = NoiseEngine()
        engine.stop(fadeDuration: 5)          // not playing → immediate path
        #expect(engine._lastStopDeactivatedSession == true)
        #expect(engine.isPlaying == false)
    }

    @Test func stopRestoresMasterVolume() {
        let engine = NoiseEngine()
        engine.masterVolume = 0.6
        engine.stop()
        #expect(abs(engine._mixerOutputVolume - 0.6) < 0.001)
    }
}
```

- [ ] **Step 2: Run to verify failure**

AudioEngine scheme command (Task 1 Step 2). Expected: BUILD FAILURE — `fadeCurve` undefined.

- [ ] **Step 3: Create Fade.swift**

```swift
/// Linear fade curve from `start` down to 0 in `steps` equal decrements.
/// The final element is always exactly 0. Empty for steps <= 0.
func fadeCurve(from start: Float, steps: Int) -> [Float] {
    guard steps > 0 else { return [] }
    return (1...steps).map { start * Float(steps - $0) / Float(steps) }
}
```

- [ ] **Step 4: Implement fade stop in NoiseEngine.swift**

Add near `fadeTask` friends:

```swift
    private var fadeTask: Task<Void, Never>?
    private static let fadeStepInterval: TimeInterval = 0.05
```

New overload + shared teardown; refactor immediate `stop` to use it:

```swift
    /// Ramps the mixer to silence over `fadeDuration`, then stops the engine.
    /// `isPlaying` flips false immediately so UI reflects the stop right away.
    public func stop(fadeDuration: TimeInterval, deactivateSession: Bool = true) {
        guard fadeDuration > 0, isPlaying else {
            stop(deactivateSession: deactivateSession)
            return
        }
        fadeTask?.cancel()
        _removeScopeTap()
        isPlaying = false
        let steps = max(1, Int(fadeDuration / Self.fadeStepInterval))
        let curve = fadeCurve(from: engine.mainMixerNode.outputVolume, steps: steps)
        fadeTask = Task { [weak self] in
            for v in curve {
                try? await Task.sleep(for: .seconds(Self.fadeStepInterval))
                if Task.isCancelled { return }
                self?.engine.mainMixerNode.outputVolume = v
            }
            guard let self, !Task.isCancelled else { return }
            self.finishStop(deactivateSession: deactivateSession)
        }
    }

    public func stop(deactivateSession: Bool = true) {
        fadeTask?.cancel()
        fadeTask = nil
        _removeScopeTap()
        finishStop(deactivateSession: deactivateSession)
        isPlaying = false
    }

    private func finishStop(deactivateSession: Bool) {
        engine.stop()
        engine.mainMixerNode.outputVolume = masterVolume   // undo any partial fade
        if deactivateSession {
            try? AVAudioSession.sharedInstance().setActive(false)
        }
        _lastStopDeactivatedSession = deactivateSession
    }
```

Update `start()` — first lines become:

```swift
    public func start() throws {
        fadeTask?.cancel()
        fadeTask = nil
        engine.mainMixerNode.outputVolume = masterVolume
        let session = AVAudioSession.sharedInstance()
        // ... rest unchanged
```

- [ ] **Step 5: Wire VM (PlaybackViewModel.swift)**

`togglePlay` — clear stale error before starting:

```swift
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
```

`stopPlayback` gains a fade parameter (manual stop = quick 0.15 s anti-click; sleep timer = gentle 10 s):

```swift
    private func stopPlayback(fade: TimeInterval = 0.15) {
        engine.stop(fadeDuration: fade)
        scopeSamples = []
        isPlaying = engine.isPlaying
    }
```

`_sleepTick` expiry branch becomes:

```swift
        if remaining <= 0 {
            cancelSleepTimer()
            stopPlayback(fade: 10)
        } else {
```

- [ ] **Step 6: Run full suite to verify pass**

Full suite command. Expected: exit=0, `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add AudioEngine/Sources/Fade.swift AudioEngine/Sources/NoiseEngine.swift AudioEngine/Tests/FadeTests.swift Sculptor/Sources/PlaybackViewModel.swift
git -c user.name='Sculptor' -c user.email='dev@sculptor.local' commit -m "feat: fade-out on stop and sleep expiry; clear stale playback error"
```

---

### Task 4: Preset loudness normalization

**Files:**
- Modify: `AudioEngine/Sources/NoisePreset.swift`
- Modify: `AudioEngine/Sources/NoiseEngine.swift` (`apply`, new `setGlobalGain`/`globalGain`)
- Modify: `Sculptor/Sources/PlaybackViewModel.swift` (`applyCustom`, `reset`, `restoreLastSelection`)
- Test: `AudioEngine/Tests/NoisePresetTests.swift` (append)

**Interfaces:**
- Produces: `NoisePreset.makeupGain: Float` (energy-normalized, clamped ±12 dB); `NoiseEngine.setGlobalGain(_ dB: Float)` and `NoiseEngine.globalGain: Float` (clamped ±24). `apply(_:)` now also sets `eq.globalGain = preset.makeupGain`.

- [ ] **Step 1: Write failing tests**

Append to `AudioEngine/Tests/NoisePresetTests.swift`:

```swift
@Test func whiteHasNoMakeupGain() {
    #expect(NoisePreset.white.makeupGain == 0)
}

@Test func darkerPresetsGetMoreMakeup() {
    #expect(NoisePreset.brown.makeupGain > NoisePreset.pink.makeupGain)
    #expect(NoisePreset.pink.makeupGain > 0)
}

@Test func makeupClampedToTwelveDB() {
    for p in NoisePreset.allCases {
        #expect(p.makeupGain.magnitude <= 12)
    }
}

@Test func applySetsGlobalGainFromPreset() {
    let engine = NoiseEngine()
    engine.apply(.brown)
    #expect(abs(engine.globalGain - NoisePreset.brown.makeupGain) < 0.01)
    engine.apply(.white)
    #expect(engine.globalGain == 0)
}
```

- [ ] **Step 2: Run to verify failure**

AudioEngine scheme command. Expected: BUILD FAILURE — `makeupGain` undefined.

- [ ] **Step 3: Implement makeupGain in NoisePreset.swift**

```swift
    /// Makeup gain so presets play at roughly equal loudness: the inverse of the
    /// mean per-band linear power, clamped ±12 dB. White (flat) → 0. Rough
    /// energy normalization — no psychoacoustic weighting; tune by ear later.
    public var makeupGain: Float {
        let g = gains
        guard !g.isEmpty else { return 0 }
        let meanPower = g.map { pow(10, $0 / 10) }.reduce(0, +) / Float(g.count)
        return min(12, max(-12, -10 * log10(meanPower)))
    }
```

- [ ] **Step 4: Implement engine side (NoiseEngine.swift)**

```swift
    /// Overall EQ output gain in dB (preset loudness makeup). Clamped ±24.
    public func setGlobalGain(_ dB: Float) {
        eq.globalGain = min(24, max(-24, dB))
    }

    public var globalGain: Float { eq.globalGain }
```

`apply(_:)` becomes:

```swift
    public func apply(_ preset: NoisePreset) {
        for (i, g) in preset.gains.enumerated() where i < eq.bands.count {
            setGain(band: i, dB: g)
        }
        setGlobalGain(preset.makeupGain)
    }
```

- [ ] **Step 5: Wire VM (PlaybackViewModel.swift)**

Custom presets and manual reset carry no makeup — add `engine.setGlobalGain(0)`:

In `applyCustom(id:gains:)`, after the `for` loop:

```swift
        engine.setGlobalGain(0)
```

In `reset()`, after the `for` loop:

```swift
        engine.setGlobalGain(0)
```

In `restoreLastSelection()`, after `selection = sel`:

```swift
        if case .builtin(let preset) = sel {
            engine.setGlobalGain(preset.makeupGain)
        } else {
            engine.setGlobalGain(0)
        }
```

- [ ] **Step 6: Run full suite to verify pass**

Full suite command. Expected: exit=0, `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add AudioEngine/Sources/NoisePreset.swift AudioEngine/Sources/NoiseEngine.swift AudioEngine/Tests/NoisePresetTests.swift Sculptor/Sources/PlaybackViewModel.swift
git -c user.name='Sculptor' -c user.email='dev@sculptor.local' commit -m "feat: energy-based preset loudness normalization via EQ global gain"
```

---

### Task 5: Media-services reset recovery

**Files:**
- Modify: `AudioEngine/Sources/NoiseEngine.swift` (make `engine`/`eq` vars; extract `makeEQ()`/`buildGraph()`; add reset observer + `_recoverFromMediaServicesReset()`)
- Test: `AudioEngine/Tests/NoiseEngineMediaResetTests.swift` (create)

**Interfaces:**
- Consumes: `masterVolume` (Task 2), `fadeTask` (Task 3), `setGlobalGain` (Task 4).
- Produces: internal `_recoverFromMediaServicesReset()`. No public API change.

- [ ] **Step 1: Write failing test**

Create `AudioEngine/Tests/NoiseEngineMediaResetTests.swift`:

```swift
import Testing
@testable import AudioEngine

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
        #expect(engine.isPlaying == false)
    }

    @Test func rebuildClearsStaleScopeTapFlag() {
        let engine = NoiseEngine()
        engine._installScopeTap()
        engine._recoverFromMediaServicesReset()
        #expect(engine.isScopeTapInstalled == false)
    }
}
```

- [ ] **Step 2: Run to verify failure**

AudioEngine scheme command. Expected: BUILD FAILURE — `_recoverFromMediaServicesReset` undefined.

- [ ] **Step 3: Restructure NoiseEngine.swift**

Change stored properties from `let` to `var`:

```swift
    private var engine = AVAudioEngine()
    private var eq: AVAudioUnitEQ
```

Extract EQ construction (replaces the band-config loop in `init`):

```swift
    private static func makeEQ() -> AVAudioUnitEQ {
        let eq = AVAudioUnitEQ(numberOfBands: AudioEngineModule.bandFrequencies.count)
        for (i, f) in AudioEngineModule.bandFrequencies.enumerated() {
            let band = eq.bands[i]
            band.filterType = .parametric
            band.frequency = f
            band.bandwidth = 1.0       // ~1 octave
            band.gain = 0
            band.bypass = false
        }
        return eq
    }
```

Extract graph wiring (replaces source-node + attach/connect code in `init`; PRNG pointers are reused so noise state survives rebuilds):

```swift
    private func buildGraph() {
        let l = stateL, r = stateR
        let sourceNode = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                for (ch, buffer) in abl.enumerated() {
                    let ptr = buffer.mData!.assumingMemoryBound(to: Float.self)
                    ptr[frame] = (ch == 0) ? l.pointee.next() : r.pointee.next()
                }
            }
            return noErr
        }
        engine.attach(sourceNode)
        engine.attach(eq)
        engine.connect(sourceNode, to: eq, format: outputFormat)
        engine.connect(eq, to: engine.mainMixerNode, format: outputFormat)
        engine.mainMixerNode.outputVolume = masterVolume
    }
```

New `init` body order: `eq = Self.makeEQ()` → `stateL/stateR.initialize(...)` → `buildGraph()` → observer registration, adding:

```swift
        nc.addObserver(self, selector: #selector(handleMediaServicesReset(_:)),
                       name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
```

Recovery:

```swift
    @objc private func handleMediaServicesReset(_ note: Notification) {
        _recoverFromMediaServicesReset()
    }

    /// mediaserverd died: every node in the old graph is invalid. Rebuild from
    /// scratch, restore EQ state, resume if we were playing. Internal for tests.
    func _recoverFromMediaServicesReset() {
        let bandGains = eq.bands.map(\.gain)
        let global = eq.globalGain
        let wasPlaying = isPlaying
        fadeTask?.cancel()
        fadeTask = nil
        scopeTapInstalled = false          // old tap died with the old graph
        engine = AVAudioEngine()
        eq = Self.makeEQ()
        buildGraph()
        for (i, g) in bandGains.enumerated() { eq.bands[i].gain = g }
        eq.globalGain = global
        isPlaying = false
        if wasPlaying { try? start() }
    }
```

- [ ] **Step 4: Run AudioEngine tests to verify pass**

AudioEngine scheme command. Expected: exit=0, `** TEST SUCCEEDED **`.

- [ ] **Step 5: Run full suite (engine is shared — check nothing else broke)**

Full suite command. Expected: exit=0, `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add AudioEngine/Sources/NoiseEngine.swift AudioEngine/Tests/NoiseEngineMediaResetTests.swift
git -c user.name='Sculptor' -c user.email='dev@sculptor.local' commit -m "feat: rebuild audio graph after media services reset"
```

---

### Task 6: Scope tap lifecycle on scenePhase

**Files:**
- Modify: `AudioEngine/Sources/NoiseEngine.swift` (`scopeEnabled`, gate in `start()`)
- Modify: `Sculptor/Sources/PlaybackViewModel.swift` (`setScopeActive`)
- Modify: `Sculptor/Sources/RootView.swift` (scenePhase)
- Test: `AudioEngine/Tests/NoiseEngineScopeTapTests.swift` (append)

**Interfaces:**
- Produces: `NoiseEngine.scopeEnabled: Bool` (default true; false removes tap, true reinstalls only if playing); `PlaybackViewModel.setScopeActive(_ active: Bool)`.

- [ ] **Step 1: Write failing tests**

Append to `AudioEngine/Tests/NoiseEngineScopeTapTests.swift`:

```swift
@Test func disablingScopeRemovesInstalledTap() {
    let engine = NoiseEngine()
    engine._installScopeTap()
    engine.scopeEnabled = false
    #expect(engine.isScopeTapInstalled == false)
}

@Test func enablingScopeWhileStoppedDoesNotInstall() {
    let engine = NoiseEngine()
    engine.scopeEnabled = false
    engine.scopeEnabled = true
    #expect(engine.isScopeTapInstalled == false)   // not playing — nothing to observe
}
```

- [ ] **Step 2: Run to verify failure**

AudioEngine scheme command. Expected: BUILD FAILURE — `scopeEnabled` undefined.

- [ ] **Step 3: Implement engine side (NoiseEngine.swift)**

```swift
    /// Whether the oscilloscope tap should run. UI turns this off when the app
    /// leaves the foreground so we don't downsample buffers all night for a
    /// scope nobody sees.
    public var scopeEnabled = true {
        didSet {
            guard scopeEnabled != oldValue else { return }
            if scopeEnabled {
                if isPlaying { _installScopeTap() }
            } else {
                _removeScopeTap()
            }
        }
    }
```

In `start()`, change `_installScopeTap()` to:

```swift
        if scopeEnabled { _installScopeTap() }
```

- [ ] **Step 4: Wire VM + RootView**

`PlaybackViewModel`:

```swift
    /// Scene-phase hook: tear the scope tap down in background, restore in foreground.
    func setScopeActive(_ active: Bool) {
        engine.scopeEnabled = active
        if !active { scopeSamples = [] }
    }
```

`RootView` — add environment + modifier on `HomeView(...)` chain:

```swift
    @Environment(\.scenePhase) private var scenePhase
```

```swift
        .onChange(of: scenePhase) { _, phase in
            vm.setScopeActive(phase == .active)
        }
```

- [ ] **Step 5: Run full suite to verify pass**

Full suite command. Expected: exit=0, `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add AudioEngine/Sources/NoiseEngine.swift AudioEngine/Tests/NoiseEngineScopeTapTests.swift Sculptor/Sources/PlaybackViewModel.swift Sculptor/Sources/RootView.swift
git -c user.name='Sculptor' -c user.email='dev@sculptor.local' commit -m "feat: suspend scope tap while app is backgrounded"
```

---

### Task 7: Lock-screen Now Playing + remote commands

**Files:**
- Create: `Sculptor/Sources/NowPlayingService.swift`
- Modify: `Sculptor/Sources/PlaybackViewModel.swift`
- Modify: `Sculptor/Sources/HomeView.swift`
- Test: `Sculptor/Tests/PlaybackViewModelTests.swift` (append)

**Interfaces:**
- Consumes: `togglePlay()`, `isPlaying`, `presetDisplayName`.
- Produces: `NowPlayingService` (init with `onPlay`/`onPause`/`onToggle` closures; `update(title:isPlaying:)`); `PlaybackViewModel.nowPlayingTitle: String` (`@Published`, pushed by HomeView which resolves custom-preset names via `@Query`).

- [ ] **Step 1: Write failing test**

Append inside `PlaybackViewModelTests` suite:

```swift
    @Test func nowPlayingTitlePublishesToInfoCenter() {
        let vm = PlaybackViewModel(defaults: freshDefaults())
        vm.nowPlayingTitle = "Rain Machine"
        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        #expect(info?[MPMediaItemPropertyTitle] as? String == "Rain Machine")
        #expect(info?[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 0)
    }
```

Add `import MediaPlayer` at top of the test file.

- [ ] **Step 2: Run to verify failure**

Full suite command. Expected: BUILD FAILURE — `nowPlayingTitle` undefined.

- [ ] **Step 3: Create NowPlayingService.swift**

```swift
import MediaPlayer

/// Lock-screen / Control Center integration: publishes Now Playing metadata and
/// routes remote commands (lock screen, AirPods) back to the view model.
final class NowPlayingService {
    private let center = MPNowPlayingInfoCenter.default()
    private var targets: [(MPRemoteCommand, Any)] = []

    init(onPlay: @escaping () -> Void,
         onPause: @escaping () -> Void,
         onToggle: @escaping () -> Void) {
        let commands = MPRemoteCommandCenter.shared()
        addTarget(commands.playCommand, onPlay)
        addTarget(commands.pauseCommand, onPause)
        addTarget(commands.togglePlayPauseCommand, onToggle)
    }

    deinit {
        for (command, target) in targets { command.removeTarget(target) }
    }

    private func addTarget(_ command: MPRemoteCommand, _ handler: @escaping () -> Void) {
        let target = command.addTarget { _ in
            handler()
            return .success
        }
        targets.append((command, target))
    }

    func update(title: String, isPlaying: Bool) {
        center.nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: "Sculptor",
            MPNowPlayingInfoPropertyIsLiveStream: true,   // endless noise — no duration/seek bar
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
    }
}
```

- [ ] **Step 4: Wire PlaybackViewModel**

Add property:

```swift
    private var nowPlaying: NowPlayingService?

    /// Resolved display title (HomeView pushes it — custom preset names need @Query).
    @Published var nowPlayingTitle = "Custom" {
        didSet { if oldValue != nowPlayingTitle { pushNowPlaying() } }
    }
```

Change `isPlaying` declaration to push on transitions:

```swift
    @Published private(set) var isPlaying = false {
        didSet { if oldValue != isPlaying { pushNowPlaying() } }
    }
```

At the END of `init` (after `restoreLastSelection()`):

```swift
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
```

Add private method:

```swift
    private func pushNowPlaying() {
        nowPlaying?.update(title: nowPlayingTitle, isPlaying: isPlaying)
    }
```

- [ ] **Step 5: Push resolved names from HomeView**

On the `ZStack` in `body`, add:

```swift
        .onChange(of: presetName, initial: true) { _, name in
            vm.nowPlayingTitle = name
        }
```

- [ ] **Step 6: Run full suite to verify pass**

Full suite command. Expected: exit=0, `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add Sculptor/Sources/NowPlayingService.swift Sculptor/Sources/PlaybackViewModel.swift Sculptor/Sources/HomeView.swift Sculptor/Tests/PlaybackViewModelTests.swift
git -c user.name='Sculptor' -c user.email='dev@sculptor.local' commit -m "feat: lock-screen Now Playing metadata and remote play/pause commands"
```

---

### Task 8: Final verification (build + run smoke)

**Files:** none (verification only)

- [ ] **Step 1: Full suite green**

Full suite command from Global Constraints. Expected: exit=0, `** TEST SUCCEEDED **`.

- [ ] **Step 2: Build and run on simulator**

Use XcodeBuildMCP (`build_run_sim`, scheme `Sculptor`, sim `iPhone Air`) or:
`xcodebuild build -workspace Sculptor.xcworkspace -scheme Sculptor -destination 'platform=iOS Simulator,name=iPhone Air' > /tmp/sculptor-build.log 2>&1; echo "exit=$?"; tail -5 /tmp/sculptor-build.log`
Expected: exit=0, app launches, volume slider visible under scope, play works.

- [ ] **Step 3: Report device-only checks to user**

Lock-screen audio continuation, lock-screen controls, and AirPods commands cannot be verified in unit tests and are unreliable in the simulator. Tell the user: verify on device — play noise, lock phone (audio continues), check lock-screen card shows preset name + play/pause works.
