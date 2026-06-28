# Phase 2B — Preset Management: 3-dot Menu + Save→Rename-Mode Handoff

**Date:** 2026-06-28
**Status:** Approved (design), ready for implementation planning
**Predecessors:** Phase 2A (IA restructure — Home + Sculpt sheet + Presets page).

## Context

Phase 2A deferred two preset-management items:
- YOUR PRESETS **3-dot menu** (Rename / Copy / Delete).
- The **Save → opens Presets in rename mode** handoff (2A's Save did a plain name-alert insert + dismiss).

This phase adds both. Rename is **inline** (the row's title becomes a focused `TextField`), copies and new saves **append to the end** of YOUR PRESETS, and the Save handoff opens the Presets page with the new preset focused for renaming. The sheet→page transition is **sequenced via `onDismiss`** to avoid a present-while-dismissing race, and rename focus is driven from the row's lifecycle (not the navigation handler) so the keyboard reliably appears after the transition.

## Goals

1. Add a 3-dot menu to each custom preset row: **Rename**, **Copy**, **Delete**.
2. Inline rename: tap Rename → the title becomes a focused `TextField`; commit on Return/submit.
3. Copy a preset (appends "Copy of …" at the end of the list).
4. Replace both Save entry points (Sculpt sheet + Presets page) with an insert-then-inline-rename flow.
5. Wire the Sculpt-sheet Save to dismiss the sheet and open the Presets page with the new preset in rename mode.

## Non-Goals (Phase 2B)

- Sleep-timer (moon button) — **Phase 2C**.
- Stereo width, gentle drift, Dynamic Type, light theme, iCloud sync (still deferred).
- "Copy of Copy of …" de-duplication / numbering (the simple stacked prefix is acceptable).
- Reordering changes — 2A's `.onMove` drag-reorder is unchanged.

## Architecture

```
PlaybackViewModel
  + @Published var presetToRename: UUID?      // sole cross-view coordination flag

RootView
  HomeView(...)
    .sheet(isPresented:$showSculpt, onDismiss: { if vm.presetToRename != nil { showPresets = true } }) {
        SculptSheet(vm:)
    }
    .fullScreenCover(isPresented:$showPresets) { PresetsView(vm:) }

SculptSheet  — Save: insert default preset, set vm.presetToRename, dismiss (no alert)
PresetsView  — owns renamingID + @FocusState; consumes vm.presetToRename on appear
CustomPresetRow (Sculptor target) — normal row OR inline rename TextField; trailing 3-dot Menu
```

- One shared `PlaybackViewModel` (`@StateObject` in `RootView`, `@ObservedObject` elsewhere), per the existing rule.
- Cross-view coordination uses **VM `@Published` state** (`presetToRename`), not callback closures. Menu-action handlers (Rename/Copy/Delete) are intra-component closures passed from `PresetsView` to `CustomPresetRow` — these are button wiring, not cross-view navigation state.

## Component 1 — PlaybackViewModel

- Add `@Published var presetToRename: UUID?` (default `nil`). This is UI-coordination state only; the VM does not touch SwiftData.
- No other VM changes.

**Tests:** setting and clearing `presetToRename`.

## Component 2 — Pure helpers (PresetMetrics.swift)

Add two pure free functions (unit-testable, no SwiftData):

```swift
/// Name for a duplicated preset.
func copyName(of name: String) -> String {
    "Copy of \(name)"
}

/// Resolves a rename submission: trimmed; empty reverts to the old name.
func sanitizedRename(old: String, new: String) -> String {
    let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? old : trimmed
}
```

**Tests:** `copyName("Late night") == "Copy of Late night"`; `sanitizedRename(old:"X", new:"  ") == "X"`; `sanitizedRename(old:"X", new:" Hi ") == "Hi"`.

## Component 3 — CustomPresetRow (Sculptor target)

A new app-target view (`Sculptor/Sources/CustomPresetRow.swift`) for custom-preset rows (built-ins keep the plain DesignSystem `PresetRow`).

`CustomPresetRow`:
- Inputs: `name: String`, `subtitle: String`, `gains: [Float]`, `isActive: Bool`, `isRenaming: Bool`, `renameText: Binding<String>`, and four closures `onBeginRename: () -> Void`, `onCommitRename: () -> Void`, `onCopy: () -> Void`, `onDelete: () -> Void`. A `FocusState<Bool>.Binding` is passed in for the field.
- Layout: `MiniEQIcon(gains:)` (40×28) + a content area:
  - When `isRenaming`: a `TextField` bound to `renameText`, focused, `.onSubmit { onCommitRename() }`, `.submitLabel(.done)`.
  - Else: title (`DockType.font(16,.semibold)`, primary) + subtitle (`DockType.font(12)`, tertiary).
- Trailing: when **not** renaming, a 3-dot `Menu` (`ellipsis` / `ellipsis.circle`) with buttons: **Rename** (sets renaming — handled by parent via the same path that toggles `isRenaming`), **Copy** → `onCopy`, **Delete** (`role: .destructive`) → `onDelete`. The active checkmark (`checkmark`, accent) shows when `isActive && !isRenaming`.
- `.contentShape(Rectangle())` so the row tap (apply) works in the non-renaming state.

Rename activation: the **Rename** menu item calls a parent closure `onBeginRename()` that sets `renamingID` + seeds `renameText`. Focus is set from the row via `.task(id: isRenaming)` (focus true when it becomes the renaming row), so it survives the navigation transition.

(Pure presentational; verified via build + screenshots.)

## Component 4 — PresetsView

- Add `@State private var renamingID: UUID?`, `@State private var renameText = ""`, `@FocusState private var renameFieldFocused: Bool`.
- Remove `@State showingSave`, `@State newName`, and the Save alert.
- Render custom presets via `CustomPresetRow`:
  - `isRenaming: renamingID == preset.id`
  - `renameText: $renameText`
  - tap (apply) only fires when `renamingID == nil` (a renaming row must not apply on field tap).
  - `onBeginRename`: `renameText = preset.name; renamingID = preset.id`.
  - `onCommitRename`: `preset.name = sanitizedRename(old: preset.name, new: renameText); renamingID = nil`.
  - `onCopy`: insert `CustomPreset(name: copyName(of: preset.name), gains: preset.gains, sortIndex: max+1)`.
  - `onDelete`: `context.delete(preset)`.
- Keep swipe-to-delete (`.onDelete`) and drag-reorder (`.onMove`) from 2A.
- **Save current as preset** button → insert `CustomPreset(name:"Custom", gains: vm.gains, sortIndex: max+1)`, then `renamingID = newID; renameText = "Custom"` (inline rename immediately; page already open). No alert.
- **Handoff consumption:** on appear / on change of `vm.presetToRename` — if non-nil, set `renamingID = id`, seed `renameText` from that preset's name, then clear `vm.presetToRename`. Use `.onChange(of: vm.presetToRename)` plus a check in `.onAppear` (cover may present with the value already set).

## Component 5 — SculptSheet

- Remove `@State showingSave`, `@State newName`, the `.alert`, and `savePreset()`'s `dismiss()`-only flow.
- **Save as preset** button → insert `CustomPreset(name:"Custom", gains: vm.gains, sortIndex: max+1)`, set `vm.presetToRename = newPreset.id`, then `dismiss()`. No alert.
- The sheet no longer opens Presets itself; `RootView`'s `onDismiss` does (sequenced).

## Component 6 — RootView

- `.sheet(isPresented: $showSculpt, onDismiss: { if vm.presetToRename != nil { showPresets = true } }) { SculptSheet(vm: vm) }`.
- `.fullScreenCover(isPresented: $showPresets) { PresetsView(vm: vm) }` (unchanged).
- This sequences the transition: the sheet fully dismisses, then the cover presents in `onDismiss`. No simultaneous present/dismiss.

## Data Flow

```
Save (sheet)  → insert "Custom" preset → vm.presetToRename = id → dismiss sheet
              → RootView onDismiss sees presetToRename → showPresets = true
              → PresetsView appears → renamingID = id, seed renameText, clear vm.presetToRename
              → CustomPresetRow .task focuses field → user types name → onSubmit commits
Save (page)   → insert "Custom" preset → renamingID = id (inline, no handoff)
3-dot Rename  → onBeginRename → renamingID = preset.id, renameText = name → focus → commit
3-dot Copy    → insert "Copy of <name>" at end
3-dot Delete  → context.delete(preset)
rename commit → preset.name = sanitizedRename(old:new:) → renamingID = nil
```

## Error Handling

- Empty/whitespace rename submission → revert to the existing name (never persist blank).
- The Save flow creates the preset immediately (named "Custom"); there is no "cancel" that removes it — renaming is the naming step. Leaving the field as "Custom" is a valid outcome.
- Copy never fails; stacked "Copy of Copy of …" names are acceptable.
- Presenting/dismissing does not affect playback.

## Testing

- **PlaybackViewModel:** `presetToRename` set then clear.
- **Helpers:** `copyName`; `sanitizedRename` (trim, empty-revert, normal).
- **Row / handoff / menu:** build + launch + screenshots of (a) 3-dot menu open, (b) a row in inline-rename with the field focused, (c) Presets page reached via Save handoff with the new preset focused. (No UI-tap tool: best-effort screenshots; rely on build + VM/helper tests + code review.)
- Swift Testing, pristine output.

## Global Constraints (carried)

- iOS 17.0 floor; Tuist-only generation (no committed `.xcodeproj`/`.xcworkspace`).
- Band frequencies 60/125/250/500/1000/2000/4000/8000 Hz; gain range −24…+12 dB.
- RT-safe render callback untouched.
- Bundle id prefix `com.sculptor`. Dark theme only.
- Font PostScript names `Dock-Lexend-*` via `DockType.font`.
- ONE `PlaybackViewModel` as `@StateObject` in `RootView`, `@ObservedObject` elsewhere.
- Cross-view coordination via `@Published` VM state, not callback closures.
- Swift Testing, pristine output.

## Open Items (deferred)

- 2C: sleep-timer (moon) auto-stop.
- Stereo width, gentle drift, Dynamic Type, light theme, iCloud sync.
