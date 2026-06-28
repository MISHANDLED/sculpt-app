# Phase 1C — Presets (built-in list + custom save/persist/reorder/delete)

**Date:** 2026-06-28
**Status:** Approved (sections 1–6), ready for implementation planning
**Predecessors:** Phase 1A (DesignSystem + Sculpt), Phase 1B (`2026-06-28-phase1b-nowplaying-visualizer-design.md` — 3-tab shell + Now Playing + scope; the Presets tab is currently a placeholder).

## Context

Phase 1B added the 3-tab shell with a `PresetsPlaceholderView`. Phase 1C fills the Presets tab with the designed content (`sculptor_design/screenshots/home2.png`/`sheet.png`, right panel): a built-in preset section, a "YOUR PRESETS" section of user-saved custom presets, and a "+ Save current as preset" action. Custom presets persist across launches via SwiftData.

## Goals

1. Persist custom presets (name + 8 gains + order) with SwiftData.
2. Presets tab: built-in section (5 `NoisePreset`s) + custom section (user presets).
3. Save the current EQ as a named custom preset.
4. Apply any preset (built-in or custom) with an active checkmark; reorder and delete custom presets.

## Non-Goals (Phase 1C)

- Rename of an existing custom preset (deferred to a later polish pass).
- A 3-dot per-row menu (the design shows one; this phase uses native swipe-to-delete + drag-to-reorder instead — simpler, fully covers delete + reorder).
- iCloud sync / sharing / export.
- Stereo width, gentle drift, Dynamic Type, light theme (still deferred).

## Architecture

```
SculptorApp
  .modelContainer(for: CustomPreset.self)      ← SwiftData container at root
  └─ RootTabView (shared PlaybackViewModel)
       ├─ NowPlayingView (vm)
       ├─ SculptView (vm)
       └─ PresetsView (vm)                       ← replaces PresetsPlaceholderView
            @Environment(\.modelContext)
            @Query(sort: \.sortIndex) custom presets
```

- **`CustomPreset`** is a SwiftData `@Model` in the Sculptor target.
- Persistence lives in the **view layer** (`@Query` + `@Environment(\.modelContext)`); `PlaybackViewModel` stays SwiftData-free — it only applies gains and tracks the active selection. This keeps the VM unit-testable without a model container.
- DesignSystem stays a pure visual layer; new components (`MiniEQIcon`, `PresetRow`) take plain values.

## Component 1 — CustomPreset model (Sculptor target)

```swift
@Model final class CustomPreset {
    var id: UUID
    var name: String
    var gains: [Float]      // 8 values, matches band frequencies
    var sortIndex: Int
    var createdAt: Date
    init(id: UUID = UUID(), name: String, gains: [Float], sortIndex: Int, createdAt: Date = .now)
}
```

- `gains` stores the 8 band gains (SwiftData persists a `[Float]` attribute).
- `sortIndex` defines display order (ascending); reorder rewrites it.
- Tests use an in-memory `ModelContainer` (`ModelConfiguration(isStoredInMemoryOnly: true)`).

## Component 2 — Unified selection model (`PlaybackViewModel`)

Replace `selectedPreset: NoisePreset?` with:

```swift
enum PresetSelection: Equatable {
    case none
    case builtin(NoisePreset)
    case custom(UUID)
}
@Published private(set) var selection: PresetSelection = .none
```

- `select(_ preset: NoisePreset)` → applies preset gains, `selection = .builtin(preset)` (existing behavior, new selection value).
- `applyCustom(id: UUID, gains: [Float])` → engine applies each band gain (clamped via `setGain`), publishes `gains`, `selection = .custom(id)`.
- `setGain(band:dB:)` (slider drag) → `selection = .none` (was: `selectedPreset = nil`).
- `PresetChipsRow` (Now Playing + Sculpt) highlights a chip when `vm.selection == .builtin(preset)`; its tap still calls `vm.select(preset)`. Update `PresetChipsRow` and `PlaybackViewModelTests` accordingly.

## Component 3 — DesignSystem components

- **`MiniEQIcon(gains: [Float])`** — the small bar glyph from the design: renders the gains as tiny vertical bars (teal) in a compact frame. Pure helper `miniEQBarHeight(gain: Float, range: ClosedRange<Float>, maxHeight: CGFloat) -> CGFloat` (clamped, monotonic), unit-tested; the view is dumb/previewable.
- **`PresetRow`** — a row view: leading `MiniEQIcon`, title (`DockType` semibold) + subtitle (tertiary), trailing teal checkmark when `isActive`. `PresetRow(title:subtitle:gains:isActive:)`. Reused for built-in and custom rows.

## Component 4 — PresetsView (Sculptor target, replaces PresetsPlaceholderView)

- `PresetsView(vm: PlaybackViewModel)`:
  - **Built-in section:** the 5 `NoisePreset`s (white/pink/brown/grey/speechBlocker) with name + description text, each a `PresetRow` (gains = `preset.gains`, `isActive = vm.selection == .builtin(preset)`); tap → `vm.select(preset)`.
  - **"YOUR PRESETS" section:** `@Query(sort: \CustomPreset.sortIndex)` rows; each a `PresetRow` (gains = preset.gains, subtitle "Custom · N bands raised", `isActive = vm.selection == .custom(preset.id)`); tap → `vm.applyCustom(id: preset.id, gains: preset.gains)`.
    - **Reorder:** `.onMove` rewrites `sortIndex` across affected rows.
    - **Delete:** swipe-to-delete / `.onDelete` removes from `modelContext`.
    - **Empty state:** when no custom presets, a gentle message under the header.
  - **"+ Save current as preset":** button → name-entry alert (`TextField`); on confirm, insert `CustomPreset(name: trimmedName, gains: vm.gains, sortIndex: <maxSortIndex + 1>)` into `modelContext`. Empty/whitespace name → fall back to a default ("Custom") or disable confirm.
- `RootTabView` swaps `PresetsPlaceholderView()` → `PresetsView(vm: vm)`; `PresetsPlaceholderView` is deleted.
- `SculptorApp` adds `.modelContainer(for: CustomPreset.self)`.

## Component 5 — Helpers

- `bandsRaisedCount(_ gains: [Float]) -> Int` — count of bands with gain > 0 (for "Custom · N bands raised"). Pure, tested. Lives in the Sculptor target.

## Data Flow

```
Save:    "+ Save" → name alert → CustomPreset(name, vm.gains, sortIndex:max+1) → modelContext.insert → @Query refreshes
Apply built-in: row tap → vm.select(preset) → engine applies → selection=.builtin → checkmark + chips update
Apply custom:   row tap → vm.applyCustom(id,gains) → engine applies → selection=.custom(id) → checkmark
Drag band:      vm.setGain → selection=.none → all checkmarks/chips clear
Reorder:        .onMove → rewrite sortIndex on affected presets → save
Delete:         .onDelete → modelContext.delete(preset)
```

## Error Handling

- Save with empty/whitespace name → confirm disabled (or default name); never persist an empty name.
- `gains` array always length 8 (sourced from `vm.gains`); applying a custom preset clamps via `setGain`.
- SwiftData context save failures are non-fatal to playback; surface nothing blocking (log).

## Testing

- **CustomPreset / persistence** (in-memory `ModelContainer`): insert + fetch; delete; `@Query` ordering by `sortIndex`; reorder rewrites indices to the expected order.
- **PlaybackViewModel:** `select` → `.builtin`; `applyCustom` → `.custom(id)` and gains updated; `setGain` → `.none`. (Replaces the old `selectedPreset`-nil test.)
- **Helpers:** `bandsRaisedCount` (zeros → 0; mixed → correct count); `miniEQBarHeight` (clamps, monotonic, min for ≤ range.lowerBound).
- **PresetsView:** composition — verified via the smoke run/screenshot (built-in + custom sections, save, reorder, delete, checkmark).
- Swift Testing, pristine output.

## Global Constraints (carried)

- iOS 17.0 floor; Tuist-only generation (no committed `.xcodeproj`/`.xcworkspace`).
- Band frequencies 60/125/250/500/1000/2000/4000/8000 Hz; gain range −24…+12 dB clamped in `setGain`.
- RT-safe render callback untouched.
- Bundle id prefix `com.sculptor`. Dark theme only.
- Font PostScript names are `Dock-Lexend-*` (use `DockType.font`).
- Swift Testing, pristine output.

## Open Items (deferred)

- Rename custom presets; per-row 3-dot menu.
- iCloud sync / export.
- Stereo width, gentle drift, Dynamic Type, light theme.
