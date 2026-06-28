# Phase 1C — Presets (built-in + custom save/persist/reorder/delete) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fill the Presets tab with a built-in preset list plus user-saved custom presets (SwiftData) that can be applied, reordered, and deleted.

**Architecture:** A SwiftData `@Model CustomPreset` is persisted via a `ModelContainer` attached at `SculptorApp`. `PresetsView` (replacing the placeholder) reads custom presets with `@Query` and writes via `@Environment(\.modelContext)`. The shared `PlaybackViewModel` gains a unified `PresetSelection` enum (built-in / custom / none) so both the chip rows and the preset list reflect one active selection. DesignSystem adds `MiniEQIcon` and `PresetRow`.

**Tech Stack:** Swift 6, SwiftUI (List, @Query, alert), SwiftData (@Model, ModelContainer), Tuist 4.x, Swift Testing.

## Global Constraints

- iOS 17.0 deployment floor.
- Tuist-only generation — never hand-edit `.xcodeproj`/`.xcworkspace` (gitignored); after adding files run `tuist generate --no-open`. NO new Tuist targets (new files fall under existing `**` globs).
- Band frequencies (8): `60,125,250,500,1000,2000,4000,8000`; gain range `-24…+12` dB clamped in `NoiseEngine.setGain`.
- RT-safe render callback untouched.
- Bundle id prefix `com.sculptor`. Dark theme only.
- Font PostScript names are `Dock-Lexend-*`; use `DockType.font(_:_:)` for text.
- Swift Testing (`import Testing`, `@Test`, `#expect`); test output pristine.
- Commit with `git -c user.name='Sculptor' -c user.email='dev@sculptor.local' commit ...`.
- Standard simulator destination: `platform=iOS Simulator,name=iPhone 17 Pro`.

## File Structure

**Sculptor (modify/create):**
- `Sculptor/Sources/PlaybackViewModel.swift` (modify) — `PresetSelection` enum, `selection`, `applyCustom`.
- `Sculptor/Sources/PresetChipsRow.swift` (modify) — selection-enum highlight.
- `Sculptor/Sources/CustomPreset.swift` (new) — SwiftData `@Model`.
- `Sculptor/Sources/PresetMetrics.swift` (new) — `bandsRaisedCount`.
- `Sculptor/Sources/PresetsView.swift` (new) — the tab content.
- `Sculptor/Sources/RootTabView.swift` (modify) — swap placeholder → `PresetsView`.
- `Sculptor/Sources/PresetsPlaceholderView.swift` (delete, Task 6).
- `Sculptor/Sources/SculptorApp.swift` (modify) — `.modelContainer`.
- `Sculptor/Tests/*` — VM selection, CustomPreset persistence, bandsRaisedCount.

**DesignSystem (create):**
- `DesignSystem/Sources/Components/MiniEQIcon.swift` (new) — `miniEQBarHeight` + view.
- `DesignSystem/Sources/Components/PresetRow.swift` (new).
- `DesignSystem/Tests/MiniEQIconTests.swift` (new).

---

### Task 1: Unified PresetSelection in PlaybackViewModel

**Files:**
- Modify: `Sculptor/Sources/PlaybackViewModel.swift`
- Modify: `Sculptor/Sources/PresetChipsRow.swift`
- Modify: `Sculptor/Tests/PlaybackViewModelTests.swift`

**Interfaces:**
- Consumes: `NoiseEngine`, `NoisePreset`.
- Produces: `enum PresetSelection: Equatable { case none, builtin(NoisePreset), custom(UUID) }`; `PlaybackViewModel.selection: PresetSelection` (replaces `selectedPreset`); `func applyCustom(id: UUID, gains: [Float])`. `select(_:)` sets `.builtin`; `setGain` sets `.none`.

- [ ] **Step 1: Update the failing tests**

Replace `Sculptor/Tests/PlaybackViewModelTests.swift` with:
```swift
import Testing
@testable import Sculptor
import AudioEngine
import Foundation

@MainActor
@Test func selectPresetSetsBuiltinSelection() {
    let vm = PlaybackViewModel()
    vm.select(.pink)
    #expect(vm.gains == NoisePreset.pink.gains)
    #expect(vm.selection == .builtin(.pink))
}

@MainActor
@Test func applyCustomSetsCustomSelectionAndGains() {
    let vm = PlaybackViewModel()
    let id = UUID()
    let g: [Float] = [3, 2, 1, 0, -1, -2, -3, -4]
    vm.applyCustom(id: id, gains: g)
    #expect(vm.gains == g)
    #expect(vm.selection == .custom(id))
}

@MainActor
@Test func draggingABandClearsSelection() {
    let vm = PlaybackViewModel()
    vm.select(.pink)
    vm.setGain(band: 0, dB: 5)
    #expect(vm.selection == .none)
    #expect(vm.gains[0] == 5)
}

@MainActor
@Test func ingestScopeSamplesIgnoredWhenPaused() {
    let vm = PlaybackViewModel()
    vm._ingestScopeSamples([1, 2, 3])
    #expect(vm.scopeSamples == [])
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -workspace Sculptor.xcworkspace -scheme Sculptor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SculptorTests/PlaybackViewModelTests`
Expected: FAIL — `selection` / `PresetSelection` / `applyCustom` not found.

- [ ] **Step 3: Edit `PlaybackViewModel.swift`**

Add the enum above the class:
```swift
enum PresetSelection: Equatable {
    case none
    case builtin(NoisePreset)
    case custom(UUID)
}
```

Replace the `selectedPreset` property:
```swift
    @Published private(set) var selectedPreset: NoisePreset?
```
with:
```swift
    @Published private(set) var selection: PresetSelection = .none
```

In `setGain`, replace `selectedPreset = nil` with `selection = .none`.

In `select(_:)`, replace `selectedPreset = preset` with `selection = .builtin(preset)`.

Add a new method after `select(_:)`:
```swift
    /// Applies an explicit gain set (a saved custom preset) and marks it active.
    func applyCustom(id: UUID, gains newGains: [Float]) {
        for (i, g) in newGains.enumerated() where i < frequencies.count {
            engine.setGain(band: i, dB: g)
        }
        gains = newGains
        selection = .custom(id)
    }
```

Add `import Foundation` at the top if not already present (for `UUID`).

- [ ] **Step 4: Update `PresetChipsRow.swift`**

Change the chip's `isSelected` argument from:
```swift
                    PresetChip(title: title, isSelected: vm.selectedPreset == preset) {
```
to:
```swift
                    PresetChip(title: title, isSelected: vm.selection == .builtin(preset)) {
```

- [ ] **Step 5: Run tests to verify they pass + app compiles**

Run: `xcodebuild test -workspace Sculptor.xcworkspace -scheme Sculptor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SculptorTests/PlaybackViewModelTests`
Expected: PASS (4 tests). App target compiles (NowPlaying/Sculpt views build via PresetChipsRow).

- [ ] **Step 6: Commit**

```bash
git add Sculptor/Sources/PlaybackViewModel.swift Sculptor/Sources/PresetChipsRow.swift Sculptor/Tests/PlaybackViewModelTests.swift
git -c user.name='Sculptor' -c user.email='dev@sculptor.local' commit -m "refactor: unified PresetSelection with built-in and custom"
```

---

### Task 2: CustomPreset SwiftData model

**Files:**
- Create: `Sculptor/Sources/CustomPreset.swift`
- Create: `Sculptor/Tests/CustomPresetTests.swift`

**Interfaces:**
- Produces: `@Model final class CustomPreset` with `id: UUID`, `name: String`, `gains: [Float]`, `sortIndex: Int`, `createdAt: Date`, and `init(id:name:gains:sortIndex:createdAt:)`.

- [ ] **Step 1: Write the failing tests**

`Sculptor/Tests/CustomPresetTests.swift`:
```swift
import Testing
import SwiftData
import Foundation
@testable import Sculptor

@MainActor
private func makeContext() throws -> ModelContext {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: CustomPreset.self, configurations: config)
    return ModelContext(container)
}

@MainActor
@Test func insertAndFetchRoundTrips() throws {
    let ctx = try makeContext()
    ctx.insert(CustomPreset(name: "Late night", gains: [1,2,3,4,5,6,7,8], sortIndex: 0))
    try ctx.save()
    let fetched = try ctx.fetch(FetchDescriptor<CustomPreset>())
    #expect(fetched.count == 1)
    #expect(fetched.first?.name == "Late night")
    #expect(fetched.first?.gains == [1,2,3,4,5,6,7,8])
}

@MainActor
@Test func fetchSortsBySortIndex() throws {
    let ctx = try makeContext()
    ctx.insert(CustomPreset(name: "B", gains: Array(repeating: 0, count: 8), sortIndex: 1))
    ctx.insert(CustomPreset(name: "A", gains: Array(repeating: 0, count: 8), sortIndex: 0))
    try ctx.save()
    let fetched = try ctx.fetch(
        FetchDescriptor<CustomPreset>(sortBy: [SortDescriptor(\.sortIndex)])
    )
    #expect(fetched.map(\.name) == ["A", "B"])
}

@MainActor
@Test func deleteRemovesPreset() throws {
    let ctx = try makeContext()
    let p = CustomPreset(name: "X", gains: Array(repeating: 0, count: 8), sortIndex: 0)
    ctx.insert(p)
    try ctx.save()
    ctx.delete(p)
    try ctx.save()
    #expect(try ctx.fetch(FetchDescriptor<CustomPreset>()).isEmpty)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `tuist generate --no-open && xcodebuild test -workspace Sculptor.xcworkspace -scheme Sculptor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SculptorTests/CustomPresetTests`
Expected: FAIL — `CustomPreset` not found.

- [ ] **Step 3: Implement `CustomPreset.swift`**

```swift
import Foundation
import SwiftData

/// A user-saved EQ preset. Persisted with SwiftData.
@Model
final class CustomPreset {
    var id: UUID
    var name: String
    var gains: [Float]
    var sortIndex: Int
    var createdAt: Date

    init(id: UUID = UUID(), name: String, gains: [Float], sortIndex: Int, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.gains = gains
        self.sortIndex = sortIndex
        self.createdAt = createdAt
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -workspace Sculptor.xcworkspace -scheme Sculptor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SculptorTests/CustomPresetTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sculptor/Sources/CustomPreset.swift Sculptor/Tests/CustomPresetTests.swift
git -c user.name='Sculptor' -c user.email='dev@sculptor.local' commit -m "feat: add CustomPreset SwiftData model"
```

---

### Task 3: MiniEQIcon component (DesignSystem)

**Files:**
- Create: `DesignSystem/Sources/Components/MiniEQIcon.swift`
- Create: `DesignSystem/Tests/MiniEQIconTests.swift`

**Interfaces:**
- Consumes: `DockColor`.
- Produces: `public func miniEQBarHeight(gain: Float, range: ClosedRange<Float>, maxHeight: CGFloat) -> CGFloat`; `MiniEQIcon(gains: [Float])` view.

- [ ] **Step 1: Write the failing test**

`DesignSystem/Tests/MiniEQIconTests.swift`:
```swift
import Testing
@testable import DesignSystem

@Test func barHeightMapsRange() {
    let r: ClosedRange<Float> = -24...12
    #expect(miniEQBarHeight(gain: 12, range: r, maxHeight: 20) == 20)   // top -> full
    #expect(miniEQBarHeight(gain: -24, range: r, maxHeight: 20) == 0)   // bottom -> empty
}

@Test func barHeightClampsAndIsMonotonic() {
    let r: ClosedRange<Float> = -24...12
    #expect(miniEQBarHeight(gain: 100, range: r, maxHeight: 20) == 20)
    #expect(miniEQBarHeight(gain: -100, range: r, maxHeight: 20) == 0)
    #expect(miniEQBarHeight(gain: 0, range: r, maxHeight: 20)
            > miniEQBarHeight(gain: -12, range: r, maxHeight: 20))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -workspace Sculptor.xcworkspace -scheme DesignSystem -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:DesignSystemTests/MiniEQIconTests`
Expected: FAIL — `miniEQBarHeight` not defined.

- [ ] **Step 3: Implement `MiniEQIcon.swift`**

```swift
import SwiftUI

/// Height of one mini-EQ bar for `gain` within `range`, clamped to 0...maxHeight.
public func miniEQBarHeight(gain: Float, range: ClosedRange<Float>, maxHeight: CGFloat) -> CGFloat {
    let clamped = min(range.upperBound, max(range.lowerBound, gain))
    let span = range.upperBound - range.lowerBound
    guard span > 0 else { return 0 }
    return maxHeight * CGFloat((clamped - range.lowerBound) / span)
}

/// Compact glyph rendering a gain set as tiny teal bars (the preset-row icon).
public struct MiniEQIcon: View {
    private let gains: [Float]
    private let range: ClosedRange<Float>

    public init(gains: [Float], range: ClosedRange<Float> = -24...12) {
        self.gains = gains
        self.range = range
    }

    public var body: some View {
        GeometryReader { geo in
            let maxH = geo.size.height
            let count = max(gains.count, 1)
            let barW = geo.size.width / CGFloat(count) * 0.6
            HStack(alignment: .bottom, spacing: geo.size.width / CGFloat(count) * 0.4) {
                ForEach(0..<gains.count, id: \.self) { i in
                    Capsule()
                        .fill(DockColor.accent)
                        .frame(width: barW,
                               height: max(1, miniEQBarHeight(gain: gains[i], range: range, maxHeight: maxH)))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

#Preview {
    MiniEQIcon(gains: [10, 6, 2, -2, -6, -2, 4, 8])
        .frame(width: 40, height: 28)
        .padding()
        .background(DockColor.background)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -workspace Sculptor.xcworkspace -scheme DesignSystem -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:DesignSystemTests/MiniEQIconTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add DesignSystem/Sources/Components/MiniEQIcon.swift DesignSystem/Tests/MiniEQIconTests.swift
git -c user.name='Sculptor' -c user.email='dev@sculptor.local' commit -m "feat: add MiniEQIcon component"
```

---

### Task 4: PresetRow component (DesignSystem)

**Files:**
- Create: `DesignSystem/Sources/Components/PresetRow.swift`

**Interfaces:**
- Consumes: `DockColor`, `DockType`, `DockSpacing`, `MiniEQIcon`.
- Produces: `PresetRow(title: String, subtitle: String, gains: [Float], isActive: Bool)`.

Pure presentational view; verified via `#Preview` and the Task 6/8 smoke. No unit test.

- [ ] **Step 1: Implement `PresetRow.swift`**

```swift
import SwiftUI

/// A preset list row: mini-EQ glyph, title + subtitle, and a teal checkmark when active.
public struct PresetRow: View {
    private let title: String
    private let subtitle: String
    private let gains: [Float]
    private let isActive: Bool

    public init(title: String, subtitle: String, gains: [Float], isActive: Bool) {
        self.title = title
        self.subtitle = subtitle
        self.gains = gains
        self.isActive = isActive
    }

    public var body: some View {
        HStack(spacing: DockSpacing.md) {
            MiniEQIcon(gains: gains)
                .frame(width: 40, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DockType.font(16, .semibold))
                    .foregroundStyle(DockColor.textPrimary)
                Text(subtitle)
                    .font(DockType.font(12))
                    .foregroundStyle(DockColor.textTertiary)
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(DockColor.accent)
            }
        }
        .padding(.vertical, DockSpacing.sm)
        .contentShape(Rectangle())
    }
}

#Preview {
    VStack {
        PresetRow(title: "Brown", subtitle: "Deep, low-end rumble",
                  gains: [10, 7, 4, 1, -2, -5, -8, -11], isActive: true)
        PresetRow(title: "Late night", subtitle: "Custom · 3 bands raised",
                  gains: [4, 3, 2, 0, 0, 0, 0, 0], isActive: false)
    }
    .padding()
    .background(DockColor.background)
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `tuist generate --no-open && xcodebuild build -workspace Sculptor.xcworkspace -scheme DesignSystem -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add DesignSystem/Sources/Components/PresetRow.swift
git -c user.name='Sculptor' -c user.email='dev@sculptor.local' commit -m "feat: add PresetRow component"
```

---

### Task 5: bandsRaisedCount helper (Sculptor)

**Files:**
- Create: `Sculptor/Sources/PresetMetrics.swift`
- Create: `Sculptor/Tests/PresetMetricsTests.swift`

**Interfaces:**
- Produces: `func bandsRaisedCount(_ gains: [Float]) -> Int` (count of gains strictly > 0).

- [ ] **Step 1: Write the failing test**

`Sculptor/Tests/PresetMetricsTests.swift`:
```swift
import Testing
@testable import Sculptor

@Test func bandsRaisedCountsPositiveGains() {
    #expect(bandsRaisedCount([0, 0, 0, 0, 0, 0, 0, 0]) == 0)
    #expect(bandsRaisedCount([3, 0, 2, -1, 0, 5, 0, 0]) == 3)
    #expect(bandsRaisedCount([-1, -2, -3]) == 0)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -workspace Sculptor.xcworkspace -scheme Sculptor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SculptorTests/PresetMetricsTests`
Expected: FAIL — `bandsRaisedCount` not defined.

- [ ] **Step 3: Implement `PresetMetrics.swift`**

```swift
import Foundation

/// Number of bands raised above flat (gain strictly greater than 0).
func bandsRaisedCount(_ gains: [Float]) -> Int {
    gains.filter { $0 > 0 }.count
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -workspace Sculptor.xcworkspace -scheme Sculptor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SculptorTests/PresetMetricsTests`
Expected: PASS (1 test, 3 expectations).

- [ ] **Step 5: Commit**

```bash
git add Sculptor/Sources/PresetMetrics.swift Sculptor/Tests/PresetMetricsTests.swift
git -c user.name='Sculptor' -c user.email='dev@sculptor.local' commit -m "feat: add bandsRaisedCount helper"
```

---

### Task 6: PresetsView (built-in + custom display) + wiring

**Files:**
- Create: `Sculptor/Sources/PresetsView.swift`
- Modify: `Sculptor/Sources/RootTabView.swift`
- Delete: `Sculptor/Sources/PresetsPlaceholderView.swift`
- Modify: `Sculptor/Sources/SculptorApp.swift`

**Interfaces:**
- Consumes: `PlaybackViewModel`, `PresetSelection`, `NoisePreset`, `CustomPreset`, `PresetRow`, `bandsRaisedCount`, `DockColor`, `DockType`, `DockSpacing`.
- Produces: `PresetsView(vm: PlaybackViewModel)`. (Save/reorder/delete added in Tasks 7–8.)

- [ ] **Step 1: Create `PresetsView.swift`** (built-in + custom display, apply, checkmark; empty state)

```swift
import SwiftUI
import SwiftData
import AudioEngine
import DesignSystem

struct PresetsView: View {
    @ObservedObject var vm: PlaybackViewModel
    @Environment(\.modelContext) private var context
    @Query(sort: \CustomPreset.sortIndex) private var customPresets: [CustomPreset]

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
            List {
                Section {
                    ForEach(builtins, id: \.0) { preset, title, subtitle in
                        PresetRow(title: title, subtitle: subtitle, gains: preset.gains,
                                  isActive: vm.selection == .builtin(preset))
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
                            PresetRow(title: preset.name,
                                      subtitle: "Custom · \(bandsRaisedCount(preset.gains)) bands raised",
                                      gains: preset.gains,
                                      isActive: vm.selection == .custom(preset.id))
                                .listRowBackground(DockColor.surface1)
                                .onTapGesture { vm.applyCustom(id: preset.id, gains: preset.gains) }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }
}

#Preview {
    PresetsView(vm: PlaybackViewModel())
        .modelContainer(for: CustomPreset.self, inMemory: true)
}
```

- [ ] **Step 2: Swap the placeholder in `RootTabView.swift`**

Replace:
```swift
            PresetsPlaceholderView()
                .tabItem { Label(AppTab.presets.title, systemImage: AppTab.presets.systemImage) }
                .tag(AppTab.presets)
```
with:
```swift
            PresetsView(vm: vm)
                .tabItem { Label(AppTab.presets.title, systemImage: AppTab.presets.systemImage) }
                .tag(AppTab.presets)
```

- [ ] **Step 3: Delete the placeholder**

Run: `git rm Sculptor/Sources/PresetsPlaceholderView.swift`

- [ ] **Step 4: Attach the model container in `SculptorApp.swift`**

```swift
import SwiftUI
import SwiftData

@main
struct SculptorApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(for: CustomPreset.self)
    }
}
```

- [ ] **Step 5: Generate, build, run, screenshot**

Run: `tuist generate --no-open` then build + install + launch on iPhone 17 Pro sim; capture a screenshot to `.superpowers/sdd/task-6-screenshot.png`.
Expected: Presets tab shows the built-in section (Brown/Pink/White/Grey/Speech blocker with mini-EQ glyphs + descriptions) and a "Your presets" section showing "No custom presets yet". Tapping a built-in row applies it and shows a teal checkmark; switching to Sculpt shows the matching sliders. No crash.

- [ ] **Step 6: Run the Sculptor suite**

Run: `xcodebuild test -workspace Sculptor.xcworkspace -scheme Sculptor -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add Sculptor/Sources/PresetsView.swift Sculptor/Sources/RootTabView.swift Sculptor/Sources/SculptorApp.swift
git -c user.name='Sculptor' -c user.email='dev@sculptor.local' commit -m "feat: Presets tab with built-in and custom sections"
```

---

### Task 7: Save current as preset

**Files:**
- Modify: `Sculptor/Sources/PresetsView.swift`

**Interfaces:**
- Consumes: `modelContext`, `vm.gains`, `customPresets`, `CustomPreset`.
- Produces: a "+ Save current as preset" affordance that inserts a `CustomPreset`.

- [ ] **Step 1: Add save state + UI to `PresetsView`**

Add state properties to the struct:
```swift
    @State private var showingSave = false
    @State private var newName = ""
```

Add a third `Section` after the "Your presets" section (inside the `List`):
```swift
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
```

Add the alert modifier to the `List` (after `.scrollContentBackground(.hidden)`):
```swift
            .alert("Save preset", isPresented: $showingSave) {
                TextField("Name", text: $newName)
                Button("Save") { savePreset() }
                Button("Cancel", role: .cancel) {}
            }
```

Add the save method to the struct:
```swift
    private func savePreset() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "Custom" : trimmed
        let nextIndex = (customPresets.map(\.sortIndex).max() ?? -1) + 1
        context.insert(CustomPreset(name: name, gains: vm.gains, sortIndex: nextIndex))
    }
```

- [ ] **Step 2: Generate, build, run, screenshot the save flow**

Run: `tuist generate --no-open` then build + run; in the app: go to Sculpt, raise a couple of bands; on Presets, tap "Save current as preset", type a name, Save; capture a screenshot to `.superpowers/sdd/task-7-screenshot.png` showing the new preset under "Your presets" with "Custom · N bands raised".
Expected: the saved preset appears; tapping it applies its gains (checkmark). No crash.

- [ ] **Step 3: Run the Sculptor suite**

Run: `xcodebuild test -workspace Sculptor.xcworkspace -scheme Sculptor -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: all pass (existing tests still green; persistence covered by Task 2).

- [ ] **Step 4: Commit**

```bash
git add Sculptor/Sources/PresetsView.swift
git -c user.name='Sculptor' -c user.email='dev@sculptor.local' commit -m "feat: save current EQ as a custom preset"
```

---

### Task 8: Reorder + delete custom presets + final verification

**Files:**
- Modify: `Sculptor/Sources/PresetsView.swift`

**Interfaces:**
- Consumes: `customPresets`, `modelContext`.
- Produces: `.onMove` (rewrites `sortIndex`) and `.onDelete` on the custom section, plus an `EditButton` to expose reorder/delete.

- [ ] **Step 1: Add reorder + delete to the custom `ForEach`**

In the non-empty branch of the "Your presets" section, attach to the `ForEach(customPresets)`:
```swift
                        .onMove { indices, newOffset in
                            var items = customPresets
                            items.move(fromOffsets: indices, toOffset: newOffset)
                            for (i, p) in items.enumerated() { p.sortIndex = i }
                        }
                        .onDelete { offsets in
                            for i in offsets { context.delete(customPresets[i]) }
                        }
```

Add a toolbar with an `EditButton` to the `List` (after the `.alert(...)` modifier):
```swift
            .toolbar { EditButton() }
```

Wrap `PresetsView`'s `body` content in a `NavigationStack` so the toolbar/EditButton renders (replace the outer `ZStack { ... }` with `NavigationStack { ZStack { ... }.navigationTitle("Presets").navigationBarTitleDisplayMode(.inline) }`). Keep the dark background.

- [ ] **Step 2: Generate, build, run, screenshot reorder + delete**

Run: `tuist generate --no-open` then build + run; in the app (after saving 2+ custom presets), tap Edit, drag to reorder and swipe/delete one; capture `.superpowers/sdd/task-8-screenshot.png` showing edit mode with reorder handles.
Expected: reorder persists (order survives leaving/returning to the tab); delete removes the preset. No crash.

- [ ] **Step 3: Run all three full suites**

Run:
```bash
xcodebuild test -workspace Sculptor.xcworkspace -scheme AudioEngine -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild test -workspace Sculptor.xcworkspace -scheme DesignSystem -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild test -workspace Sculptor.xcworkspace -scheme Sculptor -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```
Expected: all green, output pristine.

- [ ] **Step 4: Commit**

```bash
git add Sculptor/Sources/PresetsView.swift
git -c user.name='Sculptor' -c user.email='dev@sculptor.local' commit -m "feat: reorder and delete custom presets"
```

---

## Self-Review

**Spec coverage:**
- SwiftData `CustomPreset` model + root container → Tasks 2, 6. ✅
- Unified `PresetSelection` (built-in/custom/none), `applyCustom` → Task 1. ✅
- `MiniEQIcon` + `PresetRow` → Tasks 3, 4. ✅
- PresetsView built-in section + custom section + apply + checkmark → Task 6. ✅
- Save current as preset → Task 7. ✅
- Reorder + delete → Task 8. ✅
- `bandsRaisedCount` "N bands raised" → Task 5. ✅
- PresetChipsRow updated to selection enum → Task 1. ✅
- Empty state → Task 6. ✅
- Persistence/ordering/delete tested (in-memory container) → Task 2. ✅

**Placeholder scan:** No TBD/TODO; all code shown; commands concrete. Reorder/delete UI is smoke-verified (Task 8) while ordering persistence is unit-tested (Task 2) — acceptable, the index-rewrite uses stdlib `Array.move`. ✅

**Type consistency:** `PresetSelection`/`selection`/`applyCustom(id:gains:)` defined in Task 1, consumed in Task 6; `CustomPreset(id/name/gains/sortIndex/createdAt)` defined Task 2, consumed Tasks 6–8; `miniEQBarHeight`/`MiniEQIcon` Task 3 → `PresetRow` Task 4 → PresetsView Task 6; `bandsRaisedCount` Task 5 → Task 6. `select`/`setGain`/`gains` unchanged signatures. Names consistent. ✅

**Ordering safety:** Task 1 keeps the app compiling (PresetChipsRow updated in the same task as the VM change). PresetsPlaceholderView remains until Task 6 deletes it and swaps in PresetsView together. The model container is added in Task 6 alongside the first `@Query` consumer. Every intermediate state compiles. ✅
