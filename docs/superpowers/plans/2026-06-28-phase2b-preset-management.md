# Phase 2B — Preset Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a 3-dot menu (Rename / Copy / Delete) to custom preset rows with inline rename, and replace the Save flow with insert-then-inline-rename, including the Sculpt-sheet → Presets-page rename handoff.

**Architecture:** A single `@Published var presetToRename: UUID?` on `PlaybackViewModel` coordinates the sheet→page handoff; `RootView` sequences the transition in the sheet's `onDismiss`. A new `CustomPresetRow` (Sculptor target) renders custom rows with inline rename + 3-dot menu. Rename focus is driven from the row's `.task(id:)` so it survives the navigation transition.

**Tech Stack:** SwiftUI (iOS 17+), SwiftData, AudioEngine module, DesignSystem module, Swift Testing, Tuist.

## Global Constraints

- iOS 17.0 floor; Tuist-only generation — run `tuist generate` before any build; no committed `.xcodeproj`/`.xcworkspace`.
- Band frequencies `[60, 125, 250, 500, 1000, 2000, 4000, 8000]` Hz; gain range `−24…+12 dB`.
- RT-safe render callback in `NoiseEngine` must not be touched.
- Bundle id prefix `com.sculptor`. Dark theme only.
- Font via `DockType.font(_:_:)`; colors via `DockColor.*`; spacing via `DockSpacing.*`.
- ONE `PlaybackViewModel` as `@StateObject` in `RootView`, `@ObservedObject` elsewhere.
- Cross-view coordination via `@Published` VM state, not callback closures (menu-action closures within a row are fine — they are button wiring).
- Swift Testing (`@Suite`, `@Test`, `#expect`) — pristine output, zero warnings.
- Test scheme: `Sculptor` (via xcodebuild MCP `test_sim`, or `xcodebuild test -scheme Sculptor`). Session default sim is "iPhone 17 Pro".
- Commit prefix: `feat:` new code, `refactor:` deletes/renames, `test:` test-only.

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `Sculptor/Sources/PlaybackViewModel.swift` | Add `presetToRename: UUID?` |
| Modify | `Sculptor/Tests/PlaybackViewModelTests.swift` | Test set/clear of `presetToRename` |
| Modify | `Sculptor/Sources/PresetMetrics.swift` | Add `copyName(of:)`, `sanitizedRename(old:new:)` |
| Modify | `Sculptor/Tests/PresetMetricsTests.swift` | Test the two helpers |
| **Create** | `Sculptor/Sources/CustomPresetRow.swift` | Custom-preset row: inline rename + 3-dot menu |
| Modify | `Sculptor/Sources/PresetsView.swift` | Use CustomPresetRow; rename state; handoff; Save→insert+rename; drop alert |
| Modify | `Sculptor/Sources/SculptSheet.swift` | Save→insert+set flag+dismiss; drop alert |
| Modify | `Sculptor/Sources/RootView.swift` | `onDismiss` sequencing of sheet→cover |

---

### Task 1: PlaybackViewModel — presetToRename flag

**Files:**
- Modify: `Sculptor/Sources/PlaybackViewModel.swift`
- Modify: `Sculptor/Tests/PlaybackViewModelTests.swift`

**Interfaces:**
- Produces: `@Published var presetToRename: UUID?` (read/write; default `nil`)

- [ ] **Step 1: Write the failing test**

Add this test inside the `PlaybackViewModelTests` suite in `Sculptor/Tests/PlaybackViewModelTests.swift` (after the existing `noneDisplayName` test):

```swift
    @Test func presetToRenameSetAndClear() {
        let vm = PlaybackViewModel()
        #expect(vm.presetToRename == nil)
        let id = UUID()
        vm.presetToRename = id
        #expect(vm.presetToRename == id)
        vm.presetToRename = nil
        #expect(vm.presetToRename == nil)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/devansh.mohata@zomato.com/Documents/Random/Noise && tuist generate && xcodebuild test -scheme Sculptor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "presetToRename|error:|Build FAILED"`
Expected: compile error — `value of type 'PlaybackViewModel' has no member 'presetToRename'`.

- [ ] **Step 3: Add the property**

In `Sculptor/Sources/PlaybackViewModel.swift`, add after the `@Published var errorText: String?` line:

```swift
    /// UI-coordination flag: the custom preset (by id) that should enter inline rename.
    /// Set by SculptSheet's Save to hand off to PresetsView; cleared once consumed.
    @Published var presetToRename: UUID?
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Sculptor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "Test Suite.*passed|failed|error:"`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sculptor/Sources/PlaybackViewModel.swift Sculptor/Tests/PlaybackViewModelTests.swift
git commit -m "feat: PlaybackViewModel.presetToRename coordination flag

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 2: Pure helpers — copyName + sanitizedRename

**Files:**
- Modify: `Sculptor/Sources/PresetMetrics.swift`
- Modify: `Sculptor/Tests/PresetMetricsTests.swift`

**Interfaces:**
- Produces: `func copyName(of name: String) -> String`; `func sanitizedRename(old: String, new: String) -> String`

- [ ] **Step 1: Write the failing tests**

Add to `Sculptor/Tests/PresetMetricsTests.swift` (inside the existing test file; if it uses a `@Suite struct`, add inside it; if it uses free `@Test func`s, add these as free functions):

```swift
@Test func copyNamePrefixesCopyOf() {
    #expect(copyName(of: "Late night") == "Copy of Late night")
}

@Test func sanitizedRenameTrimsWhitespace() {
    #expect(sanitizedRename(old: "Old", new: "  Hi  ") == "Hi")
}

@Test func sanitizedRenameEmptyRevertsToOld() {
    #expect(sanitizedRename(old: "Old", new: "   ") == "Old")
    #expect(sanitizedRename(old: "Old", new: "") == "Old")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Sculptor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "copyName|sanitizedRename|error:|Build FAILED"`
Expected: compile error — `cannot find 'copyName' in scope` / `cannot find 'sanitizedRename' in scope`.

- [ ] **Step 3: Add the helpers**

Append to `Sculptor/Sources/PresetMetrics.swift`:

```swift
/// Name for a duplicated preset.
func copyName(of name: String) -> String {
    "Copy of \(name)"
}

/// Resolves a rename submission: trimmed; an empty result reverts to the old name.
func sanitizedRename(old: String, new: String) -> String {
    let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? old : trimmed
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Sculptor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "Test Suite.*passed|failed|error:"`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sculptor/Sources/PresetMetrics.swift Sculptor/Tests/PresetMetricsTests.swift
git commit -m "feat: copyName + sanitizedRename preset helpers

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 3: CustomPresetRow component

**Files:**
- Create: `Sculptor/Sources/CustomPresetRow.swift`

**Interfaces:**
- Consumes: `MiniEQIcon(gains:)` (public, DesignSystem); `DockColor`, `DockType`, `DockSpacing`.
- Produces: `CustomPresetRow` view with inputs `name`, `subtitle`, `gains`, `isActive`, `isRenaming`, `renameText: Binding<String>`, `renameFocus: FocusState<Bool>.Binding`, and closures `onBeginRename`, `onCommitRename`, `onCopy`, `onDelete`.

- [ ] **Step 1: Create the file**

Create `Sculptor/Sources/CustomPresetRow.swift`:

```swift
import SwiftUI
import DesignSystem

/// A custom-preset list row: mini-EQ glyph, title/subtitle (or an inline rename
/// TextField), an active checkmark, and a trailing 3-dot menu (Rename/Copy/Delete).
struct CustomPresetRow: View {
    let name: String
    let subtitle: String
    let gains: [Float]
    let isActive: Bool
    let isRenaming: Bool
    @Binding var renameText: String
    var renameFocus: FocusState<Bool>.Binding
    let onBeginRename: () -> Void
    let onCommitRename: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: DockSpacing.md) {
            MiniEQIcon(gains: gains)
                .frame(width: 40, height: 28)

            if isRenaming {
                TextField("Name", text: $renameText)
                    .font(DockType.font(16, .semibold))
                    .foregroundStyle(DockColor.textPrimary)
                    .focused(renameFocus)
                    .submitLabel(.done)
                    .onSubmit { onCommitRename() }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(DockType.font(16, .semibold))
                        .foregroundStyle(DockColor.textPrimary)
                    Text(subtitle)
                        .font(DockType.font(12))
                        .foregroundStyle(DockColor.textTertiary)
                }
            }

            Spacer()

            if isActive && !isRenaming {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(DockColor.accent)
            }

            if !isRenaming {
                Menu {
                    Button { onBeginRename() } label: { Label("Rename", systemImage: "pencil") }
                    Button { onCopy() } label: { Label("Copy", systemImage: "doc.on.doc") }
                    Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DockColor.textTertiary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, DockSpacing.sm)
        .contentShape(Rectangle())
        .task(id: isRenaming) {
            if isRenaming { renameFocus.wrappedValue = true }
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `cd /Users/devansh.mohata@zomato.com/Documents/Random/Noise && tuist generate && xcodebuild build -scheme Sculptor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|warning:|Build succeeded|Build FAILED"`
Expected: `Build succeeded`, no errors/warnings from the new file. (It is not yet referenced — that is fine; this confirms it compiles.)

- [ ] **Step 3: Commit**

```bash
git add Sculptor/Sources/CustomPresetRow.swift
git commit -m "feat: CustomPresetRow — inline rename + 3-dot menu row

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 4: PresetsView — wire CustomPresetRow, rename state, handoff, Save flow

**Files:**
- Modify: `Sculptor/Sources/PresetsView.swift`

**Interfaces:**
- Consumes: `CustomPresetRow` (Task 3); `vm.presetToRename` (Task 1); `copyName`, `sanitizedRename` (Task 2); `CustomPreset(name:gains:sortIndex:)`.

- [ ] **Step 1: Replace PresetsView.swift**

Replace the entire contents of `Sculptor/Sources/PresetsView.swift` with:

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

    @State private var editMode = EditMode.inactive
    @State private var renamingID: UUID?
    @State private var renameText = ""
    @FocusState private var renameFieldFocused: Bool

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
                                CustomPresetRow(
                                    name: preset.name,
                                    subtitle: "Custom · \(bandsRaisedCount(preset.gains)) bands raised",
                                    gains: preset.gains,
                                    isActive: !vm.isEdited && vm.selection == .custom(preset.id),
                                    isRenaming: renamingID == preset.id,
                                    renameText: $renameText,
                                    renameFocus: $renameFieldFocused,
                                    onBeginRename: { beginRename(preset) },
                                    onCommitRename: { commitRename(preset) },
                                    onCopy: { copyPreset(preset) },
                                    onDelete: { context.delete(preset) }
                                )
                                .listRowBackground(DockColor.surface1)
                                .onTapGesture {
                                    guard renamingID == nil else { return }
                                    vm.applyCustom(id: preset.id, gains: preset.gains)
                                }
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
                            saveCurrentAsPreset()
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
                .environment(\.editMode, $editMode)
            }
        }
        .onAppear { consumePendingRename() }
        .onChange(of: vm.presetToRename) { _, _ in consumePendingRename() }
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
            Button(editMode == .inactive ? "Edit" : "Done") {
                editMode = editMode == .inactive ? .active : .inactive
            }
            .font(DockType.font(14, .medium))
            .foregroundStyle(DockColor.accent)
        }
        .padding(DockSpacing.xl)
    }

    // MARK: - Actions

    private func beginRename(_ preset: CustomPreset) {
        renameText = preset.name
        renamingID = preset.id
    }

    private func commitRename(_ preset: CustomPreset) {
        preset.name = sanitizedRename(old: preset.name, new: renameText)
        renamingID = nil
    }

    private func copyPreset(_ preset: CustomPreset) {
        let nextIndex = (customPresets.map(\.sortIndex).max() ?? -1) + 1
        context.insert(CustomPreset(name: copyName(of: preset.name), gains: preset.gains, sortIndex: nextIndex))
    }

    private func saveCurrentAsPreset() {
        let nextIndex = (customPresets.map(\.sortIndex).max() ?? -1) + 1
        let preset = CustomPreset(name: "Custom", gains: vm.gains, sortIndex: nextIndex)
        context.insert(preset)
        renameText = preset.name
        renamingID = preset.id
    }

    private func consumePendingRename() {
        guard let id = vm.presetToRename else { return }
        if let preset = customPresets.first(where: { $0.id == id }) {
            renameText = preset.name
            renamingID = id
        }
        vm.presetToRename = nil
    }
}

#Preview {
    PresetsView(vm: PlaybackViewModel())
        .modelContainer(for: CustomPreset.self, inMemory: true)
}
```

- [ ] **Step 2: Build to verify**

Run: `cd /Users/devansh.mohata@zomato.com/Documents/Random/Noise && tuist generate && xcodebuild build -scheme Sculptor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|warning:|Build succeeded|Build FAILED"`
Expected: `Build succeeded`, no errors/warnings.

- [ ] **Step 3: Run tests (regression)**

Run: `xcodebuild test -scheme Sculptor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "Test Suite.*passed|failed|error:"`
Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sculptor/Sources/PresetsView.swift
git commit -m "feat: PresetsView inline rename, 3-dot actions, insert-then-rename Save, handoff consume

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 5: SculptSheet — Save sets handoff flag (no alert)

**Files:**
- Modify: `Sculptor/Sources/SculptSheet.swift`

**Interfaces:**
- Consumes: `vm.presetToRename` (Task 1); `CustomPreset(name:gains:sortIndex:)`.

- [ ] **Step 1: Replace the save state and button**

In `Sculptor/Sources/SculptSheet.swift`:

(a) Remove the two state lines:

```swift
    @State private var showingSave = false
    @State private var newName = ""
```

(b) Replace the `saveButton` computed property with:

```swift
    private var saveButton: some View {
        Button {
            savePreset()
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
    }
```

(c) Replace the `savePreset()` function with:

```swift
    private func savePreset() {
        let nextIndex = (customPresets.map(\.sortIndex).max() ?? -1) + 1
        let preset = CustomPreset(name: "Custom", gains: vm.gains, sortIndex: nextIndex)
        context.insert(preset)
        vm.presetToRename = preset.id
        dismiss()
    }
```

- [ ] **Step 2: Build to verify**

Run: `cd /Users/devansh.mohata@zomato.com/Documents/Random/Noise && tuist generate && xcodebuild build -scheme Sculptor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|warning:|Build succeeded|Build FAILED"`
Expected: `Build succeeded`, no errors/warnings (no remaining references to `showingSave`/`newName`).

- [ ] **Step 3: Commit**

```bash
git add Sculptor/Sources/SculptSheet.swift
git commit -m "feat: SculptSheet Save inserts preset and hands off to rename (no alert)

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 6: RootView — sequence sheet→cover via onDismiss + sim verify

**Files:**
- Modify: `Sculptor/Sources/RootView.swift`

**Interfaces:**
- Consumes: `vm.presetToRename` (Task 1); `SculptSheet`, `PresetsView`.

- [ ] **Step 1: Add onDismiss sequencing**

Replace the entire contents of `Sculptor/Sources/RootView.swift` with:

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
        .sheet(isPresented: $showSculpt, onDismiss: {
            if vm.presetToRename != nil { showPresets = true }
        }) {
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

- [ ] **Step 2: Build to verify**

Run: `cd /Users/devansh.mohata@zomato.com/Documents/Random/Noise && tuist generate && xcodebuild build -scheme Sculptor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|warning:|Build succeeded|Build FAILED"`
Expected: `Build succeeded`.

- [ ] **Step 3: Run full test suite**

Run: `xcodebuild test -scheme Sculptor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "Test Suite.*passed|failed|error:|executed"`
Expected: all tests pass.

- [ ] **Step 4: Launch on simulator and verify the flows**

Boot/install/launch via the xcodebuild MCP tools (build_run_sim with the session defaults). Verify and screenshot:

1. **3-dot menu** — open Presets; save a preset first if list is empty; tap the ⋯ on a custom row → menu shows Rename / Copy / Delete.
2. **Inline rename** — tap Rename → the row title becomes a focused TextField (keyboard up); type a name; Return commits; the row shows the new name.
3. **Copy** — tap Copy → a "Copy of …" row appears at the end of YOUR PRESETS.
4. **Delete** — tap Delete → the row is removed.
5. **Save handoff** — from home, open Sculpt; drag a band; tap "Save as preset" → sheet dismisses, Presets page opens, the new "Custom" row is focused for inline rename.

Take a screenshot of states 1, 2, and 5. If a tap cannot be driven, capture what is reachable and note it.

- [ ] **Step 5: Commit**

```bash
git add Sculptor/Sources/RootView.swift
git commit -m "feat: RootView sequences Sculpt-sheet dismiss into Presets rename handoff

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```
