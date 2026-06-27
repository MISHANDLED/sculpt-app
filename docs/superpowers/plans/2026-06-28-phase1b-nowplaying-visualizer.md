# Phase 1B — Tab Shell + Now Playing + Scope Visualizer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wrap the app in a 3-tab shell, build the Now Playing screen with a real-audio-tap oscilloscope visualizer, and hoist a shared playback model across tabs.

**Architecture:** `RootTabView` owns one shared `PlaybackViewModel` (renamed from `SculptViewModel`) and injects it into Now Playing, Sculpt, and a Presets placeholder. `NoiseEngine` installs an `AVAudioNodeTap` on the EQ output on start/stop, downsamples each buffer to ~128 points, and hands them to the UI via `onScopeSamples`; a dumb `ScopeVisualizer` draws the glowing oscilloscope line.

**Tech Stack:** Swift 6, SwiftUI (TabView, Canvas), AVFoundation (installTap), Tuist 4.x, Swift Testing.

## Global Constraints

- iOS 17.0 deployment floor.
- Tuist-only generation — never hand-edit `.xcodeproj`/`.xcworkspace` (gitignored, regenerated via `tuist generate --no-open`). NO new Tuist targets are needed this phase (new files fall under existing `**` globs).
- Band frequencies (fixed, 8): `60,125,250,500,1000,2000,4000,8000` Hz; gain range `-24…+12` dB clamped in `NoiseEngine.setGain`.
- RT-safe render callback (the `AVAudioSourceNode` block) must NOT be modified. The new tap is a separate, non-render callback; it must not block (copy + downsample only).
- Font PostScript names are `Dock-Lexend-*` (NOT `Lexend-*`); `.ttf` filenames are `Lexend-*`. Use `DockType.font(_:_:)` for all text.
- Bundle id prefix `com.sculptor`. Dark theme only.
- Swift Testing (`import Testing`, `@Test`, `#expect`); test output pristine.
- Commit with `git -c user.name='Sculptor' -c user.email='dev@sculptor.local' commit ...` (no global git identity).
- Standard simulator destination: `platform=iOS Simulator,name=iPhone 17 Pro`.

## File Structure

**AudioEngine (modify/create):**
- `AudioEngine/Sources/Downsample.swift` (new) — pure `downsample(_:to:)`.
- `AudioEngine/Sources/NoiseEngine.swift` (modify) — scope tap install/remove + `onScopeSamples`.
- `AudioEngine/Tests/DownsampleTests.swift`, `AudioEngine/Tests/NoiseEngineScopeTapTests.swift` (new).

**DesignSystem (create):**
- `DesignSystem/Sources/Components/ScopeVisualizer.swift` (new) — `scopeY` pure helper + Canvas view.
- `DesignSystem/Sources/Components/PlayHeroButton.swift` (new).
- `DesignSystem/Tests/ScopeVisualizerTests.swift` (new).

**Sculptor (rename/create/modify):**
- `Sculptor/Sources/PlaybackViewModel.swift` (renamed from `SculptViewModel.swift`) — + `scopeSamples`.
- `Sculptor/Tests/PlaybackViewModelTests.swift` (renamed from `SculptViewModelTests.swift`).
- `Sculptor/Sources/PresetChipsRow.swift` (new) — shared chip row.
- `Sculptor/Sources/NowPlayingView.swift` (new).
- `Sculptor/Sources/RootTabView.swift` (new) — `AppTab` enum + TabView.
- `Sculptor/Sources/PresetsPlaceholderView.swift` (new).
- `Sculptor/Sources/SculptView.swift` (modify) — use `PresetChipsRow`; injected vm; drop temp transport.
- `Sculptor/Sources/SculptorApp.swift` (modify) — root `RootTabView`.

---

### Task 1: `downsample` pure helper (AudioEngine)

**Files:**
- Create: `AudioEngine/Sources/Downsample.swift`
- Create: `AudioEngine/Tests/DownsampleTests.swift`

**Interfaces:**
- Produces: `public func downsample(_ samples: [Float], to count: Int) -> [Float]`.

- [ ] **Step 1: Write the failing test**

`AudioEngine/Tests/DownsampleTests.swift`:
```swift
import Testing
@testable import AudioEngine

@Test func downsampleEmptyReturnsEmpty() {
    #expect(downsample([], to: 128) == [])
}

@Test func downsampleBlockAverages() {
    #expect(downsample([1, 2, 3, 4], to: 2) == [1.5, 3.5])
}

@Test func downsampleShorterThanCountReturnsInput() {
    #expect(downsample([1, 2, 3], to: 5) == [1, 2, 3])
}

@Test func downsampleClampsCountToAtLeastOne() {
    #expect(downsample([1, 2, 3, 4], to: 0) == [2.5])
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -workspace Sculptor.xcworkspace -scheme AudioEngine -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:AudioEngineTests/DownsampleTests`
Expected: FAIL — `downsample` not defined.

- [ ] **Step 3: Implement `Downsample.swift`**

```swift
import Foundation

/// Block-averages `samples` into exactly `count` contiguous blocks (the mean of
/// each block). `count` is clamped to >= 1. Empty input returns []. Input shorter
/// than `count` is returned unchanged.
public func downsample(_ samples: [Float], to count: Int) -> [Float] {
    let n = samples.count
    guard n > 0 else { return [] }
    let k = max(1, count)
    guard n > k else { return samples }
    var out = [Float](repeating: 0, count: k)
    for i in 0..<k {
        let lo = i * n / k
        let hi = (i + 1) * n / k
        let end = max(hi, lo + 1)
        var sum: Float = 0
        var c = 0
        for j in lo..<min(end, n) { sum += samples[j]; c += 1 }
        out[i] = c > 0 ? sum / Float(c) : 0
    }
    return out
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -workspace Sculptor.xcworkspace -scheme AudioEngine -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:AudioEngineTests/DownsampleTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add AudioEngine/Sources/Downsample.swift AudioEngine/Tests/DownsampleTests.swift
git -c user.name='Sculptor' -c user.email='dev@sculptor.local' commit -m "feat: add downsample helper for scope visualizer"
```

---

### Task 2: Scope tap on NoiseEngine (AudioEngine)

**Files:**
- Modify: `AudioEngine/Sources/NoiseEngine.swift`
- Create: `AudioEngine/Tests/NoiseEngineScopeTapTests.swift`

**Interfaces:**
- Consumes: `downsample(_:to:)` (Task 1).
- Produces: `NoiseEngine.onScopeSamples: (([Float]) -> Void)?`; internal `NoiseEngine._installScopeTap()`, `_removeScopeTap()`, `var isScopeTapInstalled: Bool`. `start()` installs the tap; `stop()` removes it.

- [ ] **Step 1: Write the failing test**

`AudioEngine/Tests/NoiseEngineScopeTapTests.swift`:
```swift
import Testing
@testable import AudioEngine

@Test func scopeTapInstallAndRemoveToggleState() {
    let engine = NoiseEngine()
    #expect(engine.isScopeTapInstalled == false)
    engine._installScopeTap()
    #expect(engine.isScopeTapInstalled == true)
    engine._installScopeTap()  // idempotent
    #expect(engine.isScopeTapInstalled == true)
    engine._removeScopeTap()
    #expect(engine.isScopeTapInstalled == false)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -workspace Sculptor.xcworkspace -scheme AudioEngine -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:AudioEngineTests/NoiseEngineScopeTapTests`
Expected: FAIL — `isScopeTapInstalled`/`_installScopeTap` not members.

- [ ] **Step 3: Add the scope tap to `NoiseEngine.swift`**

Add a stored property near `onPlaybackStateChange` (after line 27):
```swift
    /// Fired on the main queue with a downsampled (~128-point) mono window of
    /// recent output, for the Now Playing oscilloscope. Nil when no consumer.
    public var onScopeSamples: (([Float]) -> Void)?

    private var scopeTapInstalled = false
    private static let scopeBufferSize: AVAudioFrameCount = 4096
    private static let scopePointCount = 128
```

Add these methods (place them with the other internal testability seams, before the PRNG `stateL`/`stateR` block):
```swift
    /// Whether the scope tap is currently installed.
    var isScopeTapInstalled: Bool { scopeTapInstalled }

    /// Installs an output tap that downsamples each buffer and delivers it on the
    /// main queue. Idempotent. Internal (called by start(); exposed for tests).
    func _installScopeTap() {
        guard !scopeTapInstalled else { return }
        eq.installTap(onBus: 0, bufferSize: Self.scopeBufferSize, format: nil) { [weak self] buffer, _ in
            guard let self, let channel = buffer.floatChannelData?[0] else { return }
            let frames = Int(buffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channel, count: frames))
            let window = downsample(samples, to: Self.scopePointCount)
            DispatchQueue.main.async { self.onScopeSamples?(window) }
        }
        scopeTapInstalled = true
    }

    /// Removes the scope tap if installed. Idempotent.
    func _removeScopeTap() {
        guard scopeTapInstalled else { return }
        eq.removeTap(onBus: 0)
        scopeTapInstalled = false
    }
```

In `start()`, after `isPlaying = true` (line 118), add:
```swift
        _installScopeTap()
```

In `stop()`, before `engine.stop()` (so the tap is gone before the node halts), add as the first line:
```swift
        _removeScopeTap()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -workspace Sculptor.xcworkspace -scheme AudioEngine -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:AudioEngineTests/NoiseEngineScopeTapTests`
Expected: PASS.

- [ ] **Step 5: Run the full AudioEngine suite** (tap touches the shared graph)

Run: `xcodebuild test -workspace Sculptor.xcworkspace -scheme AudioEngine -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: all pass, output pristine.

- [ ] **Step 6: Commit**

```bash
git add AudioEngine/Sources/NoiseEngine.swift AudioEngine/Tests/NoiseEngineScopeTapTests.swift
git -c user.name='Sculptor' -c user.email='dev@sculptor.local' commit -m "feat: scope tap on NoiseEngine feeding downsampled samples"
```

---

### Task 3: ScopeVisualizer component (DesignSystem)

**Files:**
- Create: `DesignSystem/Sources/Components/ScopeVisualizer.swift`
- Create: `DesignSystem/Tests/ScopeVisualizerTests.swift`

**Interfaces:**
- Consumes: `DockColor`.
- Produces: `public func scopeY(value: Float, height: CGFloat) -> CGFloat`; `ScopeVisualizer(samples: [Float])` view.

- [ ] **Step 1: Write the failing test**

`DesignSystem/Tests/ScopeVisualizerTests.swift`:
```swift
import Testing
@testable import DesignSystem

@Test func scopeYCentersZero() {
    #expect(scopeY(value: 0, height: 100) == 50)
}

@Test func scopeYMapsExtremes() {
    #expect(scopeY(value: 1, height: 100) == 0)     // +1 -> top
    #expect(scopeY(value: -1, height: 100) == 100)  // -1 -> bottom
}

@Test func scopeYClampsOutOfRange() {
    #expect(scopeY(value: 5, height: 100) == 0)
    #expect(scopeY(value: -5, height: 100) == 100)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -workspace Sculptor.xcworkspace -scheme DesignSystem -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:DesignSystemTests/ScopeVisualizerTests`
Expected: FAIL — `scopeY` not defined.

- [ ] **Step 3: Implement `ScopeVisualizer.swift`**

```swift
import SwiftUI

/// Maps a sample (roughly -1...1, clamped) to a Y coordinate: 0 -> vertical
/// center, +1 -> top (0), -1 -> bottom (height).
public func scopeY(value: Float, height: CGFloat) -> CGFloat {
    let clamped = CGFloat(min(1, max(-1, value)))
    return height / 2 - clamped * (height / 2)
}

/// Oscilloscope-style visualizer: a glowing teal polyline drawn through the
/// sample window across the full width. Empty samples render a flat center line.
public struct ScopeVisualizer: View {
    private let samples: [Float]

    public init(samples: [Float]) {
        self.samples = samples
    }

    public var body: some View {
        Canvas { context, size in
            var path = Path()
            let n = samples.count
            if n < 2 {
                let mid = size.height / 2
                path.move(to: CGPoint(x: 0, y: mid))
                path.addLine(to: CGPoint(x: size.width, y: mid))
            } else {
                for i in 0..<n {
                    let x = size.width * CGFloat(i) / CGFloat(n - 1)
                    let y = scopeY(value: samples[i], height: size.height)
                    let pt = CGPoint(x: x, y: y)
                    if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
            }
            // Glow underlay + crisp line.
            context.stroke(path, with: .color(DockColor.accent.opacity(0.4)),
                           style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            context.stroke(path, with: .color(DockColor.accent),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}

#Preview {
    ScopeVisualizer(samples: (0..<128).map { sinf(Float($0) / 8) })
        .frame(height: 80)
        .padding()
        .background(DockColor.background)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -workspace Sculptor.xcworkspace -scheme DesignSystem -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:DesignSystemTests/ScopeVisualizerTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add DesignSystem/Sources/Components/ScopeVisualizer.swift DesignSystem/Tests/ScopeVisualizerTests.swift
git -c user.name='Sculptor' -c user.email='dev@sculptor.local' commit -m "feat: add ScopeVisualizer oscilloscope component"
```

---

### Task 4: PlayHeroButton component (DesignSystem)

**Files:**
- Create: `DesignSystem/Sources/Components/PlayHeroButton.swift`

**Interfaces:**
- Consumes: `DockColor`.
- Produces: `PlayHeroButton(isPlaying: Bool, action: @escaping () -> Void)`.

This is a pure presentational view (no branching logic to unit-test beyond the symbol swap); verified via `#Preview` and the Task 8 smoke test. Do not add an assert-nothing test.

- [ ] **Step 1: Implement `PlayHeroButton.swift`**

```swift
import SwiftUI

/// Large circular play/pause hero button: teal fill, glowing ring.
public struct PlayHeroButton: View {
    private let isPlaying: Bool
    private let action: () -> Void

    public init(isPlaying: Bool, action: @escaping () -> Void) {
        self.isPlaying = isPlaying
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(DockColor.accent)
                    .frame(width: 140, height: 140)
                    .shadow(color: DockColor.accent.opacity(0.6), radius: 24)
                Circle()
                    .stroke(DockColor.accent.opacity(0.5), lineWidth: 2)
                    .frame(width: 160, height: 160)
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(DockColor.background)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
    }
}

#Preview {
    VStack(spacing: 40) {
        PlayHeroButton(isPlaying: false) {}
        PlayHeroButton(isPlaying: true) {}
    }
    .padding()
    .background(DockColor.background)
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild build -workspace Sculptor.xcworkspace -scheme DesignSystem -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add DesignSystem/Sources/Components/PlayHeroButton.swift
git -c user.name='Sculptor' -c user.email='dev@sculptor.local' commit -m "feat: add PlayHeroButton component"
```

---

### Task 5: Rename SculptViewModel → PlaybackViewModel + scope samples (Sculptor)

**Files:**
- Rename: `Sculptor/Sources/SculptViewModel.swift` → `Sculptor/Sources/PlaybackViewModel.swift`
- Rename: `Sculptor/Tests/SculptViewModelTests.swift` → `Sculptor/Tests/PlaybackViewModelTests.swift`
- Modify: `Sculptor/Sources/SculptView.swift` (update type references only)

**Interfaces:**
- Consumes: `NoiseEngine.onScopeSamples` (Task 2), `NoisePreset`.
- Produces: `PlaybackViewModel` (was `SculptViewModel`): same API (`gains`, `isPlaying`, `selectedPreset`, `errorText`, `frequencies`, `togglePlay`, `setGain`, `select`) plus `@Published private(set) var scopeSamples: [Float]` and internal `func _ingestScopeSamples(_:)`.

- [ ] **Step 1: Rename the files (git mv)**

```bash
git mv Sculptor/Sources/SculptViewModel.swift Sculptor/Sources/PlaybackViewModel.swift
git mv Sculptor/Tests/SculptViewModelTests.swift Sculptor/Tests/PlaybackViewModelTests.swift
```

- [ ] **Step 2: Write/adjust the failing tests**

Replace the contents of `Sculptor/Tests/PlaybackViewModelTests.swift` with:
```swift
import Testing
@testable import Sculptor
import AudioEngine

@MainActor
@Test func selectPresetUpdatesGainsAndSelection() {
    let vm = PlaybackViewModel()
    vm.select(.pink)
    #expect(vm.gains == NoisePreset.pink.gains)
    #expect(vm.selectedPreset == .pink)
}

@MainActor
@Test func draggingABandClearsSelectedPreset() {
    let vm = PlaybackViewModel()
    vm.select(.pink)
    vm.setGain(band: 0, dB: 5)
    #expect(vm.selectedPreset == nil)
    #expect(vm.gains[0] == 5)
}

@MainActor
@Test func ingestScopeSamplesUpdatesPublishedWindow() {
    let vm = PlaybackViewModel()
    vm._ingestScopeSamples([0.1, -0.2, 0.3])
    #expect(vm.scopeSamples == [0.1, -0.2, 0.3])
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `xcodebuild test -workspace Sculptor.xcworkspace -scheme Sculptor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SculptorTests`
Expected: FAIL — `PlaybackViewModel` / `_ingestScopeSamples` not found.

- [ ] **Step 4: Rewrite `PlaybackViewModel.swift`**

```swift
import SwiftUI
import AudioEngine

@MainActor
final class PlaybackViewModel: ObservableObject {
    @Published var gains: [Float]
    @Published private(set) var isPlaying = false
    @Published private(set) var selectedPreset: NoisePreset?
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
        selectedPreset = nil
    }

    func select(_ preset: NoisePreset) {
        engine.apply(preset)
        gains = preset.gains
        selectedPreset = preset
    }

    /// Updates the published scope window. Internal seam for the engine callback and tests.
    func _ingestScopeSamples(_ window: [Float]) {
        scopeSamples = window
    }
}
```

- [ ] **Step 5: Update type references in `SculptView.swift`**

In `Sculptor/Sources/SculptView.swift`, change the line:
```swift
    @StateObject private var vm = SculptViewModel()
```
to:
```swift
    @StateObject private var vm = PlaybackViewModel()
```
(No other change in this task — SculptView still self-owns its vm here; it is hoisted in Task 8.)

- [ ] **Step 6: Run tests to verify they pass + app compiles**

Run: `xcodebuild test -workspace Sculptor.xcworkspace -scheme Sculptor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SculptorTests`
Expected: PASS (3 tests); app target compiles.

- [ ] **Step 7: Commit**

```bash
git add -A Sculptor/Sources/PlaybackViewModel.swift Sculptor/Tests/PlaybackViewModelTests.swift Sculptor/Sources/SculptView.swift
git -c user.name='Sculptor' -c user.email='dev@sculptor.local' commit -m "refactor: rename SculptViewModel to PlaybackViewModel, add scope samples"
```

---

### Task 6: Shared PresetChipsRow (Sculptor)

**Files:**
- Create: `Sculptor/Sources/PresetChipsRow.swift`
- Modify: `Sculptor/Sources/SculptView.swift`

**Interfaces:**
- Consumes: `PlaybackViewModel`, `NoisePreset`, `PresetChip`, `DockSpacing`.
- Produces: `PresetChipsRow(vm: PlaybackViewModel)` view.

Pure presentational composition; verified via `#Preview` and the Task 8 smoke. No unit test.

- [ ] **Step 1: Create `PresetChipsRow.swift`**

```swift
import SwiftUI
import AudioEngine
import DesignSystem

/// Horizontal row of preset chips, shared by Now Playing and Sculpt. Selection
/// and tap routing go through the shared PlaybackViewModel.
struct PresetChipsRow: View {
    @ObservedObject var vm: PlaybackViewModel

    private let presets: [(NoisePreset, String)] = [
        (.white, "White"), (.pink, "Pink"), (.brown, "Brown"),
        (.grey, "Grey"), (.speechBlocker, "Speech blocker")
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DockSpacing.sm) {
                ForEach(presets, id: \.0) { preset, title in
                    PresetChip(title: title, isSelected: vm.selectedPreset == preset) {
                        vm.select(preset)
                    }
                }
            }
        }
    }
}

#Preview {
    PresetChipsRow(vm: PlaybackViewModel())
        .padding()
        .background(DockColor.background)
}
```

- [ ] **Step 2: Replace the inline chip row in `SculptView.swift` with the shared component**

In `Sculptor/Sources/SculptView.swift`, delete the `private let presets:` array property and replace the inline `ScrollView(.horizontal …) { … ForEach(presets …) … }` block with:
```swift
                PresetChipsRow(vm: vm)
```
Leave the temporary `DockButton` transport in place (removed in Task 8). Remove the now-unused `presets` property and the `import AudioEngine` only if nothing else needs it (the file still uses `NoisePreset`? No — selection now lives in PresetChipsRow; keep `import AudioEngine` only if `SculptView` still references AudioEngine types. After this change SculptView no longer references NoisePreset directly, so the `import AudioEngine` line may be removed. Verify by building.)

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild build -workspace Sculptor.xcworkspace -scheme Sculptor -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: `** BUILD SUCCEEDED **` (no unused-import or unused-variable warnings — output pristine).

- [ ] **Step 4: Commit**

```bash
git add Sculptor/Sources/PresetChipsRow.swift Sculptor/Sources/SculptView.swift
git -c user.name='Sculptor' -c user.email='dev@sculptor.local' commit -m "refactor: extract shared PresetChipsRow"
```

---

### Task 7: NowPlayingView (Sculptor)

**Files:**
- Create: `Sculptor/Sources/NowPlayingView.swift`

**Interfaces:**
- Consumes: `PlaybackViewModel`, `PlayHeroButton`, `ScopeVisualizer`, `PresetChipsRow`, `DockColor`, `DockType`, `DockSpacing`.
- Produces: `NowPlayingView(vm: PlaybackViewModel)` view.

Pure presentational composition; verified via `#Preview` and the Task 8 smoke. No unit test.

- [ ] **Step 1: Create `NowPlayingView.swift`**

```swift
import SwiftUI
import DesignSystem

struct NowPlayingView: View {
    @ObservedObject var vm: PlaybackViewModel

    var body: some View {
        ZStack {
            DockColor.background.ignoresSafeArea()

            VStack(spacing: DockSpacing.xl) {
                Spacer()

                PlayHeroButton(isPlaying: vm.isPlaying) { vm.togglePlay() }

                ScopeVisualizer(samples: vm.scopeSamples)
                    .frame(height: 80)
                    .padding(.horizontal, DockSpacing.xl)

                Text(vm.isPlaying ? "Playing · tap to pause" : "Paused")
                    .font(DockType.font(12))
                    .foregroundStyle(DockColor.textTertiary)

                if let err = vm.errorText {
                    Text(err).font(DockType.font(12)).foregroundStyle(.red)
                }

                Spacer()

                PresetChipsRow(vm: vm)
                    .padding(.bottom, DockSpacing.lg)
            }
            .padding(DockSpacing.xl)
        }
    }
}

#Preview {
    NowPlayingView(vm: PlaybackViewModel())
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild build -workspace Sculptor.xcworkspace -scheme Sculptor -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Sculptor/Sources/NowPlayingView.swift
git -c user.name='Sculptor' -c user.email='dev@sculptor.local' commit -m "feat: add Now Playing screen"
```

---

### Task 8: RootTabView + hoist shared vm + app wiring + smoke (Sculptor)

**Files:**
- Create: `Sculptor/Sources/RootTabView.swift`
- Create: `Sculptor/Sources/PresetsPlaceholderView.swift`
- Modify: `Sculptor/Sources/SculptView.swift` (injected vm; remove temp transport)
- Modify: `Sculptor/Sources/SculptorApp.swift` (root `RootTabView`)
- Create: `Sculptor/Tests/AppTabTests.swift`

**Interfaces:**
- Consumes: `NowPlayingView`, `SculptView`, `PresetsPlaceholderView`, `PlaybackViewModel`, `DockColor`.
- Produces: `RootTabView`, `AppTab` enum (`nowPlaying`, `sculpt`, `presets` with `title` + `systemImage`), `PresetsPlaceholderView`.

- [ ] **Step 1: Write the failing test**

`Sculptor/Tests/AppTabTests.swift`:
```swift
import Testing
@testable import Sculptor

@Test func appTabHasThreeTabsWithTitles() {
    #expect(AppTab.allCases.count == 3)
    #expect(AppTab.nowPlaying.title == "Now Playing")
    #expect(AppTab.sculpt.title == "Sculpt")
    #expect(AppTab.presets.title == "Presets")
}

@Test func appTabSystemImages() {
    #expect(AppTab.nowPlaying.systemImage == "play.circle")
    #expect(AppTab.sculpt.systemImage == "slider.vertical.3")
    #expect(AppTab.presets.systemImage == "bookmark")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -workspace Sculptor.xcworkspace -scheme Sculptor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SculptorTests/AppTabTests`
Expected: FAIL — `AppTab` not defined.

- [ ] **Step 3: Create `PresetsPlaceholderView.swift`**

```swift
import SwiftUI
import DesignSystem

struct PresetsPlaceholderView: View {
    var body: some View {
        ZStack {
            DockColor.background.ignoresSafeArea()
            VStack(spacing: DockSpacing.sm) {
                Text("Your presets")
                    .font(DockType.font(20, .semibold))
                    .foregroundStyle(DockColor.textPrimary)
                Text("Coming soon")
                    .font(DockType.font(14))
                    .foregroundStyle(DockColor.textTertiary)
            }
        }
    }
}

#Preview { PresetsPlaceholderView() }
```

- [ ] **Step 4: Create `RootTabView.swift`**

```swift
import SwiftUI
import DesignSystem

enum AppTab: CaseIterable {
    case nowPlaying, sculpt, presets

    var title: String {
        switch self {
        case .nowPlaying: return "Now Playing"
        case .sculpt:     return "Sculpt"
        case .presets:    return "Presets"
        }
    }

    var systemImage: String {
        switch self {
        case .nowPlaying: return "play.circle"
        case .sculpt:     return "slider.vertical.3"
        case .presets:    return "bookmark"
        }
    }
}

struct RootTabView: View {
    @StateObject private var vm = PlaybackViewModel()
    @State private var selection: AppTab = .nowPlaying

    var body: some View {
        TabView(selection: $selection) {
            NowPlayingView(vm: vm)
                .tabItem { Label(AppTab.nowPlaying.title, systemImage: AppTab.nowPlaying.systemImage) }
                .tag(AppTab.nowPlaying)
            SculptView(vm: vm)
                .tabItem { Label(AppTab.sculpt.title, systemImage: AppTab.sculpt.systemImage) }
                .tag(AppTab.sculpt)
            PresetsPlaceholderView()
                .tabItem { Label(AppTab.presets.title, systemImage: AppTab.presets.systemImage) }
                .tag(AppTab.presets)
        }
        .tint(DockColor.accent)
    }
}

#Preview { RootTabView() }
```

- [ ] **Step 5: Make `SculptView` take an injected vm and drop the temp transport**

In `Sculptor/Sources/SculptView.swift`:
- Change `@StateObject private var vm = PlaybackViewModel()` to:
```swift
    @ObservedObject var vm: PlaybackViewModel
```
- Delete the temporary transport `DockButton(...)` line (the `vm.isPlaying ? "Pause" : "Play"` button) — transport now lives on the Now Playing tab.
- Update the `#Preview` at the bottom to `SculptView(vm: PlaybackViewModel())`.

- [ ] **Step 6: Root `RootTabView` in `SculptorApp.swift`**

```swift
import SwiftUI

@main
struct SculptorApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
    }
}
```

- [ ] **Step 7: Run the AppTab tests, then build + run + screenshot**

Run: `tuist generate --no-open`
Run: `xcodebuild test -workspace Sculptor.xcworkspace -scheme Sculptor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SculptorTests/AppTabTests`
Expected: PASS (2 tests).

Then build, install, launch on the iPhone 17 Pro simulator, and capture a screenshot to `.superpowers/sdd/task-8-screenshot.png`.
Expected: app launches on the **Now Playing** tab — dark bg, large teal play/pause hero, scope area below, status text, preset chip row, and a 3-tab bar (Now Playing / Sculpt / Presets) tinted teal. Tapping play starts audio and the scope line animates; the Sculpt tab shows the EQ sliders (no transport button); the Presets tab shows the placeholder. No crash.

- [ ] **Step 8: Run all three full suites**

Run (each to confirm green):
```bash
xcodebuild test -workspace Sculptor.xcworkspace -scheme AudioEngine -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild test -workspace Sculptor.xcworkspace -scheme DesignSystem -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild test -workspace Sculptor.xcworkspace -scheme Sculptor -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```
Expected: all green, output pristine.

- [ ] **Step 9: Commit**

```bash
git add Sculptor/Sources/RootTabView.swift Sculptor/Sources/PresetsPlaceholderView.swift Sculptor/Sources/SculptView.swift Sculptor/Sources/SculptorApp.swift Sculptor/Tests/AppTabTests.swift
git -c user.name='Sculptor' -c user.email='dev@sculptor.local' commit -m "feat: 3-tab shell with shared playback model"
```

---

## Self-Review

**Spec coverage:**
- 3-tab shell (Now Playing/Sculpt/Presets) → Task 8 (`RootTabView`, `AppTab`). ✅
- Rename `SculptViewModel`→`PlaybackViewModel`, hoist as shared `@StateObject` injected to tabs → Tasks 5 (rename) + 8 (hoist/inject). ✅
- Now Playing: play hero + scope + status + chips → Tasks 4 (`PlayHeroButton`), 7 (`NowPlayingView`). ✅
- Audio tap → downsample → `onScopeSamples` → published `scopeSamples` → visualizer → Tasks 1 (`downsample`), 2 (tap), 5 (`scopeSamples`), 3 (`ScopeVisualizer`). ✅
- Shared preset-chip row → Task 6 (`PresetChipsRow`). ✅
- Presets placeholder → Task 8 (`PresetsPlaceholderView`). ✅
- Drop Sculpt temporary transport → Task 8. ✅
- Render callback untouched; tap is separate callback → Task 2 (only adds tap methods + start/stop calls; render block unedited). ✅
- Testing across units → every task has tests except pure-view components (Tasks 4, 6, 7), explicitly justified and covered by the Task 8 smoke. ✅

**Placeholder scan:** No TBD/TODO; all code shown in full; commands concrete. ✅

**Type consistency:** `downsample(_:to:)` defined in Task 1, consumed in Task 2; `onScopeSamples`/`_installScopeTap`/`isScopeTapInstalled` defined in Task 2, consumed in Task 5; `scopeY`/`ScopeVisualizer` defined in Task 3, consumed in Task 7; `PlayHeroButton` defined in Task 4, consumed in Task 7; `PlaybackViewModel`/`_ingestScopeSamples`/`scopeSamples` defined in Task 5, consumed in Tasks 6–8; `PresetChipsRow` defined in Task 6, consumed in Task 7; `NowPlayingView`/`PresetsPlaceholderView`/`AppTab` defined in Tasks 7–8, consumed in Task 8. Names consistent. ✅

**Ordering safety:** Every intermediate state compiles. SculptView self-owns its vm through Tasks 5–7 (app still roots SculptView via SculptorApp from Phase 1A); the `@StateObject`→`@ObservedObject` switch and temp-transport removal happen together in Task 8 when `RootTabView` becomes the owner/root. ✅
