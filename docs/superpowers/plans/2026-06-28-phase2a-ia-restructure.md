# Phase 2A — IA Restructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 3-tab shell with the correct IA: home (NowPlaying) always visible, Sculpt opens as a bottom sheet, Presets opens as a full-screen cover.

**Architecture:** `RootView` owns one `PlaybackViewModel` and two `@State` booleans (`showSculpt`, `showPresets`); `HomeView` is the persistent root; `.sheet` presents `SculptSheet`, `.fullScreenCover` presents `PresetsView`. The tab bar (`RootTabView` + `AppTab`) is deleted entirely.

**Tech Stack:** SwiftUI (iOS 17+), SwiftData, AudioEngine module, DesignSystem module, Swift Testing, Tuist project generation.

## Global Constraints

- iOS 17.0 floor; Tuist-only generation — no committed `.xcodeproj`/`.xcworkspace`; run `tuist generate` in the repo root before any build.
- Band frequencies `[60, 125, 250, 500, 1000, 2000, 4000, 8000]` Hz; gain range `−24…+12 dB`.
- RT-safe render callback in `NoiseEngine` must not be touched.
- Bundle id prefix `com.sculptor`. Dark theme only; no light-mode paths.
- Font via `DockType.font(_:_:)`; colors via `DockColor.*`; spacing via `DockSpacing.*`.
- Swift Testing (`@Suite`, `@Test`, `#expect`) — pristine output, zero warnings, zero skips.
- Commit message prefix: `feat:` for new code, `refactor:` for deletes/renames, `test:` for test-only.

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `Sculptor/Sources/PlaybackViewModel.swift` | Add `isEdited`, fix `setGain`, add `reset()`, add `presetDisplayName` |
| Modify | `Sculptor/Tests/PlaybackViewModelTests.swift` | Update 1 stale test; add 6 new tests |
| Modify | `DesignSystem/Sources/Components/PlayHeroButton.swift` | Radial gradient fill + 3 pulsing rings |
| Modify | `Sculptor/Sources/PresetChipsRow.swift` | `isSelected` guard includes `!vm.isEdited` |
| **Create** | `Sculptor/Sources/HomeView.swift` | New home screen (top bar + hero center + bottom rail+Sculpt) |
| Delete | `Sculptor/Sources/NowPlayingView.swift` | Replaced by HomeView |
| **Create** | `Sculptor/Sources/SculptSheet.swift` | Bottom sheet: sliders + chip rail + Save alert + Reset |
| Delete | `Sculptor/Sources/SculptView.swift` | Replaced by SculptSheet |
| Modify | `Sculptor/Sources/PresetsView.swift` | Remove NavigationStack; add chevron-back header; `!vm.isEdited` active-state guard |
| **Create** | `Sculptor/Sources/RootView.swift` | Navigation shell: owns vm + showSculpt/showPresets |
| Modify | `Sculptor/Sources/SculptorApp.swift` | Root `RootView()` instead of `RootTabView()` |
| Delete | `Sculptor/Sources/RootTabView.swift` | Includes `AppTab` enum |
| Delete | `Sculptor/Tests/AppTabTests.swift` | AppTab no longer exists |

---

### Task 1: PlaybackViewModel — isEdited, setGain fix, reset, presetDisplayName

**Files:**
- Modify: `Sculptor/Sources/PlaybackViewModel.swift`
- Modify: `Sculptor/Tests/PlaybackViewModelTests.swift`

**Interfaces:**
- Produces: `@Published private(set) var isEdited: Bool`, `func reset()`, `var presetDisplayName: String`
- `setGain` no longer clears `selection`; callers (PresetChipsRow, HomeView) guard active state with `!isEdited`

- [ ] **Step 1: Write failing tests**

Replace `Sculptor/Tests/PlaybackViewModelTests.swift` with:

```swift
import Testing
@testable import Sculptor
import AudioEngine
import Foundation

@MainActor
@Suite struct PlaybackViewModelTests {
    @Test func selectPresetSetsBuiltinSelection() {
        let vm = PlaybackViewModel()
        vm.select(.pink)
        #expect(vm.gains == NoisePreset.pink.gains)
        #expect(vm.selection == .builtin(.pink))
    }

    @Test func applyCustomSetsCustomSelectionAndGains() {
        let vm = PlaybackViewModel()
        let id = UUID()
        let g: [Float] = [3, 2, 1, 0, -1, -2, -3, -4]
        vm.applyCustom(id: id, gains: g)
        #expect(vm.gains == g)
        #expect(vm.selection == .custom(id))
    }

    // UPDATED: setGain now sets isEdited=true and PRESERVES selection
    @Test func draggingABandSetsIsEditedAndPreservesSelection() {
        let vm = PlaybackViewModel()
        vm.select(.pink)
        vm.setGain(band: 0, dB: 5)
        #expect(vm.selection == .builtin(.pink))   // preserved
        #expect(vm.isEdited == true)
        #expect(vm.gains[0] == 5)
    }

    @Test func selectClearsIsEdited() {
        let vm = PlaybackViewModel()
        vm.setGain(band: 0, dB: 5)
        vm.select(.pink)
        #expect(vm.isEdited == false)
        #expect(vm.selection == .builtin(.pink))
    }

    @Test func applyCustomClearsIsEdited() {
        let vm = PlaybackViewModel()
        vm.setGain(band: 0, dB: 5)
        let id = UUID()
        vm.applyCustom(id: id, gains: [Float](repeating: 0, count: 8))
        #expect(vm.isEdited == false)
        #expect(vm.selection == .custom(id))
    }

    @Test func resetZerosGainsAndClearsState() {
        let vm = PlaybackViewModel()
        vm.select(.pink)
        vm.setGain(band: 0, dB: 5)
        vm.reset()
        #expect(vm.gains.allSatisfy { $0 == 0 })
        #expect(vm.selection == .none)
        #expect(vm.isEdited == false)
    }

    @Test func builtinDisplayName() {
        let vm = PlaybackViewModel()
        vm.select(.pink)
        #expect(vm.presetDisplayName == "Pink")
        vm.select(.white)
        #expect(vm.presetDisplayName == "White")
        vm.select(.brown)
        #expect(vm.presetDisplayName == "Brown")
        vm.select(.grey)
        #expect(vm.presetDisplayName == "Grey")
        vm.select(.speechBlocker)
        #expect(vm.presetDisplayName == "Speech blocker")
    }

    @Test func noneDisplayName() {
        let vm = PlaybackViewModel()
        #expect(vm.presetDisplayName == "Custom")
    }

    @Test func ingestScopeSamplesIgnoredWhenPaused() {
        let vm = PlaybackViewModel()
        vm._ingestScopeSamples([1, 2, 3])
        #expect(vm.scopeSamples == [])
    }
}
```

- [ ] **Step 2: Run tests — expect failures**

```bash
cd /Users/devansh.mohata@zomato.com/Documents/Random/Noise
tuist generate
xcodebuild test \
  -scheme SculptorTests \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  2>&1 | grep -E "PASSED|FAILED|error:|Build"
```

Expected: `draggingABandSetsIsEditedAndPreservesSelection`, `selectClearsIsEdited`, `applyCustomClearsIsEdited`, `resetZerosGainsAndClearsState`, `builtinDisplayName`, `noneDisplayName` — all FAILED (symbols not yet added to VM).

- [ ] **Step 3: Implement VM changes**

Replace `Sculptor/Sources/PlaybackViewModel.swift` with:

```swift
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
```

- [ ] **Step 4: Run tests — expect all pass**

```bash
xcodebuild test \
  -scheme SculptorTests \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  2>&1 | grep -E "PASSED|FAILED|error:|Build"
```

Expected: all 9 tests PASSED, zero failures.

- [ ] **Step 5: Commit**

```bash
git add Sculptor/Sources/PlaybackViewModel.swift \
        Sculptor/Tests/PlaybackViewModelTests.swift
git commit -m "feat: isEdited state, reset(), presetDisplayName; setGain preserves selection

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 2: PlayHeroButton — radial gradient + pulsing rings

**Files:**
- Modify: `DesignSystem/Sources/Components/PlayHeroButton.swift`

**Interfaces:**
- Signature unchanged: `PlayHeroButton(isPlaying: Bool, action: () -> Void)`
- Produces: teal radial-gradient orb (~138 pt) + 3 concentric rings that pulse only while `isPlaying`

- [ ] **Step 1: Implement upgraded button**

Replace `DesignSystem/Sources/Components/PlayHeroButton.swift` with:

```swift
import SwiftUI

public struct PlayHeroButton: View {
    private let isPlaying: Bool
    private let action: () -> Void
    @State private var pulsing = false

    public init(isPlaying: Bool, action: @escaping () -> Void) {
        self.isPlaying = isPlaying
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(DockColor.accent.opacity(0.35), lineWidth: 1.5)
                        .frame(width: 138 + CGFloat(i + 1) * 24,
                               height: 138 + CGFloat(i + 1) * 24)
                        .scaleEffect(pulsing ? 1.1 : 1.0)
                        .opacity(pulsing ? 0.0 : 0.5)
                        .animation(
                            pulsing
                                ? .easeOut(duration: 1.3)
                                    .repeatForever(autoreverses: false)
                                    .delay(Double(i) * 0.42)
                                : .none,
                            value: pulsing
                        )
                }
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [DockColor.accent, accentDark],
                            center: .center,
                            startRadius: 0,
                            endRadius: 69
                        )
                    )
                    .frame(width: 138, height: 138)
                    .shadow(color: DockColor.accent.opacity(0.6), radius: 24)
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(DockColor.background)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
        .onChange(of: isPlaying, initial: true) { _, playing in
            pulsing = playing
        }
    }

    private var accentDark: Color {
        // #0e7d6c — darker teal for the radial gradient inner-to-outer effect
        let (r, g, b) = dockRGB(hex: 0x0e7d6c)
        return Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

#Preview {
    VStack(spacing: 48) {
        PlayHeroButton(isPlaying: false) {}
        PlayHeroButton(isPlaying: true) {}
    }
    .padding(60)
    .background(DockColor.background)
}
```

- [ ] **Step 2: Build DesignSystem — smoke verify**

```bash
xcodebuild build \
  -scheme DesignSystem \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  2>&1 | grep -E "error:|Build succeeded|Build FAILED"
```

Expected: `Build succeeded`, zero errors.

- [ ] **Step 3: Commit**

```bash
git add DesignSystem/Sources/Components/PlayHeroButton.swift
git commit -m "feat: PlayHeroButton radial gradient orb + pulsing rings animation

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 3: PresetChipsRow — isEdited-aware active state

**Files:**
- Modify: `Sculptor/Sources/PresetChipsRow.swift`

**Interfaces:**
- Consumes: `vm.isEdited` (Bool) from Task 1
- Produces: chip highlighted only when `!vm.isEdited && vm.selection == .builtin(preset)`

- [ ] **Step 1: Update isSelected guard**

In `Sculptor/Sources/PresetChipsRow.swift`, change line 19:

```swift
// Before
PresetChip(title: title, isSelected: vm.selection == .builtin(preset)) {

// After
PresetChip(title: title, isSelected: !vm.isEdited && vm.selection == .builtin(preset)) {
```

- [ ] **Step 2: Build Sculptor — no errors**

```bash
xcodebuild build \
  -scheme Sculptor \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  2>&1 | grep -E "error:|Build succeeded|Build FAILED"
```

- [ ] **Step 3: Commit**

```bash
git add Sculptor/Sources/PresetChipsRow.swift
git commit -m "feat: PresetChipsRow active chip clears when isEdited

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 4: HomeView (replaces NowPlayingView)

**Files:**
- Create: `Sculptor/Sources/HomeView.swift`
- Delete: `Sculptor/Sources/NowPlayingView.swift`

**Interfaces:**
- Consumes: `vm.isEdited`, `vm.isPlaying`, `vm.selection`, `vm.presetDisplayName`, `vm.scopeSamples`, `vm.errorText` from Task 1; upgraded `PlayHeroButton` from Task 2
- Produces: `HomeView(vm:onOpenSculpt:onOpenPresets:onOpenTimer:)` — used by `RootView` (Task 7)

- [ ] **Step 1: Create HomeView.swift**

Create `Sculptor/Sources/HomeView.swift`:

```swift
import SwiftUI
import SwiftData
import AudioEngine
import DesignSystem

struct HomeView: View {
    @ObservedObject var vm: PlaybackViewModel
    let onOpenSculpt: () -> Void
    let onOpenPresets: () -> Void
    let onOpenTimer: () -> Void

    @Query(sort: \CustomPreset.sortIndex) private var customPresets: [CustomPreset]

    var body: some View {
        ZStack {
            DockColor.background.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()
                heroCenter
                Spacer()
                bottomRail
            }
        }
    }

    // MARK: - Sections

    private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("NOW PLAYING")
                    .font(DockType.font(10))
                    .foregroundStyle(DockColor.textTertiary)
                    .tracking(1.5)
                HStack(spacing: 8) {
                    Text(presetName)
                        .font(DockType.font(24, .semibold))
                        .foregroundStyle(DockColor.textPrimary)
                    if vm.isEdited {
                        Text("EDITED")
                            .font(DockType.font(10, .semibold))
                            .foregroundStyle(DockColor.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(DockColor.accent.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
            }
            Spacer()
            HStack(spacing: DockSpacing.sm) {
                Button(action: onOpenPresets) {
                    HStack(spacing: 4) {
                        Image(systemName: "bookmark")
                        Text("Presets")
                            .font(DockType.font(14, .medium))
                    }
                    .foregroundStyle(DockColor.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(DockColor.surface2)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(DockColor.border, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button(action: onOpenTimer) {
                    Image(systemName: "moon")
                        .font(.system(size: 16))
                        .foregroundStyle(DockColor.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(DockColor.surface2)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(DockColor.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DockSpacing.xl)
    }

    private var heroCenter: some View {
        VStack(spacing: DockSpacing.lg) {
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
        }
    }

    private var bottomRail: some View {
        HStack(spacing: DockSpacing.md) {
            PresetChipsRow(vm: vm)
            Button(action: onOpenSculpt) {
                HStack(spacing: 6) {
                    Image(systemName: "slider.vertical.3")
                    Text("Sculpt")
                }
                .font(DockType.font(16, .semibold))
                .foregroundStyle(DockColor.background)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(DockColor.accent)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(DockSpacing.xl)
    }

    // MARK: - Helpers

    private var presetName: String {
        switch vm.selection {
        case .custom(let id):
            return customPresets.first(where: { $0.id == id })?.name ?? "Custom"
        default:
            let name = vm.presetDisplayName
            return name.isEmpty ? "Custom" : name
        }
    }
}

#Preview {
    HomeView(vm: PlaybackViewModel(), onOpenSculpt: {}, onOpenPresets: {}, onOpenTimer: {})
        .modelContainer(for: CustomPreset.self, inMemory: true)
}
```

- [ ] **Step 2: Delete NowPlayingView.swift**

```bash
rm Sculptor/Sources/NowPlayingView.swift
```

- [ ] **Step 3: Build Sculptor**

```bash
tuist generate
xcodebuild build \
  -scheme Sculptor \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  2>&1 | grep -E "error:|Build succeeded|Build FAILED"
```

Expected: `Build succeeded`. If any references to `NowPlayingView` remain, the build will catch them.

- [ ] **Step 4: Commit**

```bash
git add Sculptor/Sources/HomeView.swift
git rm Sculptor/Sources/NowPlayingView.swift
git commit -m "feat: HomeView — top bar with preset name/EDITED badge, hero center, Sculpt rail button

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 5: SculptSheet (replaces SculptView)

**Files:**
- Create: `Sculptor/Sources/SculptSheet.swift`
- Delete: `Sculptor/Sources/SculptView.swift`

**Interfaces:**
- Consumes: `vm.reset()`, `vm.gains`, `vm.setGain`, `vm.frequencies`, `vm.errorText` from Task 1
- Produces: `SculptSheet(vm: PlaybackViewModel)` — used by `RootView` in `.sheet` (Task 7)

- [ ] **Step 1: Create SculptSheet.swift**

Create `Sculptor/Sources/SculptSheet.swift`:

```swift
import SwiftUI
import SwiftData
import AudioEngine
import DesignSystem

struct SculptSheet: View {
    @ObservedObject var vm: PlaybackViewModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CustomPreset.sortIndex) private var customPresets: [CustomPreset]

    @State private var showingSave = false
    @State private var newName = ""

    var body: some View {
        ZStack {
            DockColor.background.ignoresSafeArea()

            VStack(spacing: DockSpacing.xl) {
                header

                DockCard {
                    HStack(alignment: .bottom, spacing: DockSpacing.xs) {
                        ForEach(0..<8, id: \.self) { i in
                            VStack(spacing: DockSpacing.sm) {
                                BandSlider(
                                    value: Binding(
                                        get: { vm.gains[i] },
                                        set: { vm.setGain(band: i, dB: $0) }
                                    ),
                                    range: -24...12
                                )
                                .frame(maxWidth: .infinity)
                                .frame(height: 200)
                                Text(freqLabel(vm.frequencies[i]))
                                    .font(DockType.font(10, .medium))
                                    .foregroundStyle(DockColor.textTertiary)
                                    .fixedSize()
                            }
                        }
                    }
                }

                PresetChipsRow(vm: vm)

                saveButton

                if let err = vm.errorText {
                    Text(err).font(DockType.font(12)).foregroundStyle(.red)
                }

                Spacer()
            }
            .padding(DockSpacing.xl)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Sub-views

    private var header: some View {
        HStack {
            Text("Sculpt")
                .font(DockType.font(24, .semibold))
                .foregroundStyle(DockColor.textPrimary)
            Spacer()
            Button(action: { vm.reset() }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Reset")
                        .font(DockType.font(14, .medium))
                }
                .foregroundStyle(DockColor.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(DockColor.surface1)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(DockColor.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var saveButton: some View {
        Button {
            newName = ""
            showingSave = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                Text("Save as preset")
            }
            .font(DockType.font(16, .medium))
            .foregroundStyle(DockColor.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        DockColor.accent.opacity(0.6),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6])
                    )
            )
        }
        .buttonStyle(.plain)
        .alert("Save preset", isPresented: $showingSave) {
            TextField("Name", text: $newName)
            Button("Save") { savePreset() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Helpers

    private func freqLabel(_ f: Float) -> String {
        f >= 1000 ? "\(Int(f / 1000))k" : "\(Int(f))"
    }

    private func savePreset() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "Custom" : trimmed
        let nextIndex = (customPresets.map(\.sortIndex).max() ?? -1) + 1
        context.insert(CustomPreset(name: name, gains: vm.gains, sortIndex: nextIndex))
        dismiss()
    }
}

#Preview {
    Color.black
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            SculptSheet(vm: PlaybackViewModel())
                .modelContainer(for: CustomPreset.self, inMemory: true)
        }
}
```

- [ ] **Step 2: Delete SculptView.swift**

```bash
rm Sculptor/Sources/SculptView.swift
```

- [ ] **Step 3: Build Sculptor**

```bash
tuist generate
xcodebuild build \
  -scheme Sculptor \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  2>&1 | grep -E "error:|Build succeeded|Build FAILED"
```

Expected: `Build succeeded`.

- [ ] **Step 4: Commit**

```bash
git add Sculptor/Sources/SculptSheet.swift
git rm Sculptor/Sources/SculptView.swift
git commit -m "feat: SculptSheet — bottom sheet with Reset pill, band sliders, chip rail, Save alert

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 6: PresetsView — chevron-back header + isEdited-aware active state

**Files:**
- Modify: `Sculptor/Sources/PresetsView.swift`

**Interfaces:**
- Consumes: `vm.isEdited` from Task 1; `@Environment(\.dismiss)` to close fullScreenCover
- Produces: updated `PresetsView(vm:)` — used by `RootView` in `.fullScreenCover` (Task 7)

- [ ] **Step 1: Rewrite PresetsView.swift**

Replace `Sculptor/Sources/PresetsView.swift` with:

```swift
import SwiftUI
import SwiftData
import AudioEngine
import DesignSystem

struct PresetsView: View {
    @ObservedObject var vm: PlaybackViewModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CustomPreset.sortIndex) private var customPresets: [CustomPreset]

    @State private var showingSave = false
    @State private var newName = ""

    private let builtins: [(NoisePreset, String, String)] = [
        (.brown, "Brown", "Deep, low-end rumble"),
        (.pink, "Pink", "Balanced, natural tilt"),
        (.white, "White", "Flat across the spectrum"),
        (.grey, "Grey", "Equal-loudness shaped"),
        (.speechBlocker, "Speech blocker", "Masks nearby conversation")
    ]

    var body: some View {
        ZStack {
            DockColor.background.ignoresSafeArea()
            VStack(spacing: 0) {
                navHeader
                List {
                    Section {
                        ForEach(builtins, id: \.0) { preset, title, subtitle in
                            PresetRow(
                                title: title, subtitle: subtitle, gains: preset.gains,
                                isActive: !vm.isEdited && vm.selection == .builtin(preset)
                            )
                            .listRowBackground(DockColor.surface1)
                            .onTapGesture { vm.select(preset) }
                        }
                    }

                    Section("Your presets") {
                        if customPresets.isEmpty {
                            Text("No custom presets yet")
                                .font(DockType.font(12))
                                .foregroundStyle(DockColor.textTertiary)
                                .listRowBackground(DockColor.surface1)
                        } else {
                            ForEach(customPresets) { preset in
                                PresetRow(
                                    title: preset.name,
                                    subtitle: "Custom · \(bandsRaisedCount(preset.gains)) bands raised",
                                    gains: preset.gains,
                                    isActive: !vm.isEdited && vm.selection == .custom(preset.id)
                                )
                                .listRowBackground(DockColor.surface1)
                                .onTapGesture { vm.applyCustom(id: preset.id, gains: preset.gains) }
                            }
                            .onMove { indices, newOffset in
                                var items = customPresets
                                items.move(fromOffsets: indices, toOffset: newOffset)
                                for (i, p) in items.enumerated() { p.sortIndex = i }
                            }
                            .onDelete { offsets in
                                for i in offsets { context.delete(customPresets[i]) }
                            }
                        }
                    }

                    Section {
                        Button {
                            newName = ""
                            showingSave = true
                        } label: {
                            Label("Save current as preset", systemImage: "plus")
                                .font(DockType.font(16, .medium))
                                .foregroundStyle(DockColor.accent)
                        }
                        .listRowBackground(DockColor.surface1)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .alert("Save preset", isPresented: $showingSave) {
                    TextField("Name", text: $newName)
                    Button("Save") { savePreset() }
                    Button("Cancel", role: .cancel) {}
                }
                .toolbar { EditButton() }
            }
        }
    }

    private var navHeader: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DockColor.textPrimary)
            }
            .buttonStyle(.plain)
            Spacer()
            Text("Presets")
                .font(DockType.font(18, .semibold))
                .foregroundStyle(DockColor.textPrimary)
            Spacer()
            Color.clear.frame(width: 18, height: 18)
        }
        .padding(DockSpacing.xl)
    }

    private func savePreset() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "Custom" : trimmed
        let nextIndex = (customPresets.map(\.sortIndex).max() ?? -1) + 1
        context.insert(CustomPreset(name: name, gains: vm.gains, sortIndex: nextIndex))
    }
}

#Preview {
    PresetsView(vm: PlaybackViewModel())
        .modelContainer(for: CustomPreset.self, inMemory: true)
}
```

- [ ] **Step 2: Build Sculptor**

```bash
xcodebuild build \
  -scheme Sculptor \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  2>&1 | grep -E "error:|Build succeeded|Build FAILED"
```

Expected: `Build succeeded`.

- [ ] **Step 3: Commit**

```bash
git add Sculptor/Sources/PresetsView.swift
git commit -m "feat: PresetsView chevron-back header; isEdited clears active state

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 7: RootView + app wiring + cleanup

**Files:**
- Create: `Sculptor/Sources/RootView.swift`
- Modify: `Sculptor/Sources/SculptorApp.swift`
- Delete: `Sculptor/Sources/RootTabView.swift`
- Delete: `Sculptor/Tests/AppTabTests.swift`

**Interfaces:**
- Consumes: `HomeView`, `SculptSheet`, `PresetsView` from Tasks 4–6
- Produces: runnable app with correct IA

- [ ] **Step 1: Create RootView.swift**

Create `Sculptor/Sources/RootView.swift`:

```swift
import SwiftUI
import DesignSystem

struct RootView: View {
    @StateObject private var vm = PlaybackViewModel()
    @State private var showSculpt = false
    @State private var showPresets = false

    var body: some View {
        HomeView(
            vm: vm,
            onOpenSculpt: { showSculpt = true },
            onOpenPresets: { showPresets = true },
            onOpenTimer: {}
        )
        .sheet(isPresented: $showSculpt) {
            SculptSheet(vm: vm)
        }
        .fullScreenCover(isPresented: $showPresets) {
            PresetsView(vm: vm)
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: CustomPreset.self, inMemory: true)
}
```

- [ ] **Step 2: Update SculptorApp.swift**

Replace `Sculptor/Sources/SculptorApp.swift` with:

```swift
import SwiftUI
import SwiftData

@main
struct SculptorApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: CustomPreset.self)
    }
}
```

- [ ] **Step 3: Delete RootTabView.swift and AppTabTests.swift**

```bash
rm Sculptor/Sources/RootTabView.swift
rm Sculptor/Tests/AppTabTests.swift
```

- [ ] **Step 4: Build and run on simulator**

```bash
tuist generate
xcodebuild build \
  -scheme Sculptor \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  2>&1 | grep -E "error:|Build succeeded|Build FAILED"
```

Expected: `Build succeeded`, zero errors, zero warnings from changed files.

Then launch on simulator and verify:

1. **Home screen** — "NOW PLAYING" / "Custom" header visible; Presets pill and moon button top-right; PlayHeroButton center; ScopeVisualizer below button; chip rail + teal Sculpt button at bottom.
2. **Sculpt sheet** — tap Sculpt button → sheet slides up from bottom with drag indicator; "Sculpt" title + Reset pill; 8 sliders; chip rail; "Save as preset" dashed button; drag-to-dismiss works.
3. **EDITED state** — drag any slider → EDITED badge appears on home header next to preset name; active chip highlight clears.
4. **Reset** — tap Reset in sheet → gains zero; EDITED badge gone; no chip highlighted.
5. **Save as preset** — tap "Save as preset"; enter name; tap Save → sheet dismisses; open Presets → preset appears in YOUR PRESETS.
6. **Presets page** — tap Presets button → full-screen page with chevron-back; tap chevron → dismisses back to home.

Take a screenshot of each state to confirm. If launch or screenshots fail, note which state and what was shown.

- [ ] **Step 5: Run full test suite**

```bash
xcodebuild test \
  -scheme SculptorTests \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  2>&1 | grep -E "PASSED|FAILED|error:|Build"
```

Expected: all tests pass; `AppTabTests` file gone → no test for it.

- [ ] **Step 6: Commit**

```bash
git add Sculptor/Sources/RootView.swift \
        Sculptor/Sources/SculptorApp.swift
git rm Sculptor/Sources/RootTabView.swift \
       Sculptor/Tests/AppTabTests.swift
git commit -m "refactor: RootView replaces RootTabView; delete AppTab + tab tests

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```
