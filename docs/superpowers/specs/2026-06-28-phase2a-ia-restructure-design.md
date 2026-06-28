# Phase 2A — IA Restructure: Home + Sculpt Bottom Sheet + Presets Page

**Date:** 2026-06-28
**Status:** Approved (sections 1–6), ready for implementation planning
**Predecessors:** Phase 1A/1B/1C. **This phase corrects an IA mistake from 1B/1C.**

## Context

Phase 1B built a 3-tab `TabView` (Now Playing / Sculpt / Presets) by following `tabbars.png` — which is a *control exploration*, not the spec. The authoritative design (`sculptor_design/Sculptor.dc.html`, header line ~33) states:

> **No tab bar.** Now Playing is home — **Presets** is a button top-right; **Sculpt** is the teal action pinned right of the preset rail and opens as a **bottom sheet** over the dimmed home (swipe the grabber to dismiss). Tapping **Save as preset** dismisses the sheet and opens the Presets page with the new preset added at the top in rename mode.

This phase replaces the tab shell with the correct information architecture. The full design ("full parity") is decomposed into: **2A** (this — IA + home + Sculpt sheet + Presets page + EDITED state), **2B** (presets management: 3-dot Rename/Copy/Delete + save→rename-mode handoff), **2C** (sleep-timer moon button).

Components from 1A–1C are reused; the change is the navigation shell, the home layout, the play hero, and a small `PlaybackViewModel` addition.

## Goals

1. Remove the tab bar; make Now Playing the single home screen.
2. Open Sculpt (the EQ) as a dismissable bottom sheet over the dimmed home.
3. Open Presets as a presented page (chevron-back) from a top-right button.
4. Show the active preset name + an EDITED badge on home; add Reset and in-sheet Save to Sculpt.

## Non-Goals (Phase 2A)

- YOUR PRESETS 3-dot menu (Rename / Copy / Delete) and the Save→opens-Presets-in-rename-mode handoff — **Phase 2B** (2A's Save does a plain name-alert insert + dismiss).
- Sleep-timer (moon button) function — **Phase 2C** (2A shows the button as a non-functional placeholder).
- Decorative 22-bar home animation — superseded by the real-audio `ScopeVisualizer` (explicit user choice; keep Scope).
- Stereo width, gentle drift, Dynamic Type, light theme (still deferred).

## Architecture

```
SculptorApp (.modelContainer(for: CustomPreset.self))
  └─ RootView                         owns PlaybackViewModel (@StateObject)
       HomeView(vm:)                  the home screen (always visible)
       .sheet(isPresented:$showSculpt) → SculptSheet(vm:)        bottom sheet, .large detent + drag indicator
       .fullScreenCover(isPresented:$showPresets) → PresetsView(vm:)   page w/ chevron-back
```

- `RootView` replaces `RootTabView`; `AppTab` and `RootTabView` are deleted.
- `@State private var showSculpt = false`, `@State private var showPresets = false` in `RootView`, toggled by HomeView callbacks.
- Existing shared-state rule holds: ONE `PlaybackViewModel` as `@StateObject` in `RootView`, passed as `@ObservedObject` to `HomeView`, `SculptSheet`, `PresetsView`.

## Component 1 — PlaybackViewModel changes

- Add `@Published private(set) var isEdited = false`.
- `select(_:)` and `applyCustom(id:gains:)` → set `isEdited = false` (in addition to existing behavior).
- `setGain(band:dB:)` → set `isEdited = true` and **do NOT clear `selection`** (was `selection = .none`). This keeps the active preset name on the home header while flagging it edited.
- Add `func reset()` → set all `gains` to 0, call `engine.setGain(band:dB:0)` for each band, `selection = .none`, `isEdited = false`.
- Add `var presetDisplayName: String` → `.builtin(p)` → p's display name (White/Pink/Brown/Grey/"Speech blocker"); `.custom(id)` → resolved by the view (VM can't see SwiftData) so expose the raw selection and let the view map custom id→name; for `.none` → "Custom". (Built-in name mapping lives in the VM or a small pure helper; custom name is resolved in `PresetsView`/`HomeView` from the `@Query`.)
- "Active" for chips/checkmarks becomes `!isEdited && selection == .builtin(preset)` (and `.custom(id)` analogously). Update `PresetChipsRow` and `PresetsView` accordingly.

Tests: `select`/`applyCustom` clear `isEdited`; `setGain` sets `isEdited` and preserves `selection`; `reset` zeroes gains + clears selection/edited; built-in display-name helper.

## Component 2 — Upgraded PlayHeroButton (DesignSystem)

- Extend `PlayHeroButton(isPlaying:action:)`:
  - Background: radial gradient `#2ED3B7 → #0e7d6c` (teal orb), ~138 pt.
  - Three concentric pulsing rings (1.5 pt teal stroke) that animate (scale + fade) only while `isPlaying` (a repeating animation gated on `isPlaying`); static when paused.
  - Keep the play/pause SF Symbol centered, `DockColor.background` foreground.
- Pure presentational; previewed in both states. (No new unit test; smoke-verified.)

## Component 3 — HomeView (Sculptor target, replaces NowPlayingView)

`HomeView(vm: PlaybackViewModel, onOpenSculpt: () -> Void, onOpenPresets: () -> Void, onOpenTimer: () -> Void)`:

- **Top bar** (`HStack`, top-aligned):
  - Left `VStack`: "NOW PLAYING" overline (`DockType` 10, tertiary, uppercase) + `HStack` of preset name (`DockType` 24–26 semibold, primary) and, when `vm.isEdited`, an "EDITED" teal pill badge.
  - Right `HStack`: a **Presets** pill (`bookmark` icon + "Presets", surface2/border) → `onOpenPresets`; a circular **moon** button (`moon` / `bedtime` SF Symbol, surface2/border) → `onOpenTimer` (placeholder this phase).
- **Center** (`Spacer`-centered): `PlayHeroButton(isPlaying: vm.isPlaying){ vm.togglePlay() }`; `ScopeVisualizer(samples: vm.scopeSamples)`; play-hint text ("Playing · tap to pause" / "Paused").
- **Bottom** (`HStack`): `PresetChipsRow(vm: vm)` (flex, scrolls) + a pinned teal **Sculpt** button (`slider.vertical.3`/tune icon + "Sculpt", `DockColor.accent` bg, `DockColor.background` fg) → `onOpenSculpt`.
- Dark background; Dock tokens; Lexend.

## Component 4 — SculptSheet (Sculptor target, replaces SculptView)

`SculptSheet(vm: PlaybackViewModel)`:

- Presented via `.sheet` with `.presentationDetents([.large])` and `.presentationDragIndicator(.visible)` (the grabber).
- Header `HStack`: "Sculpt" title (24 semibold) + a **Reset** pill (`restart`/`arrow.counterclockwise` icon + "Reset", surface1/border) → `vm.reset()`.
- The 8 vertical `BandSlider`s in a `DockCard` with freq labels (the current SculptView body).
- `PresetChipsRow(vm: vm)` (the in-sheet rail).
- A **Save as preset** button (dashed border, accent text, `plus` icon) → name-entry alert (`TextField`) → insert `CustomPreset(name: trimmed-or-"Custom", gains: vm.gains, sortIndex: max+1)` into the model context, then dismiss the sheet. (Uses `@Environment(\.modelContext)` + `@Query` for sortIndex max, like PresetsView.)
- Dark background; Dock tokens.

## Component 5 — PresetsView as a presented page

- Add a top header row: a chevron-back button (`chevron.left`) that dismisses (via `@Environment(\.dismiss)`), plus a "Presets" title.
- Keep the existing BUILT-IN section, YOUR PRESETS section (`@Query`), reorder (`.onMove`) and delete (`.onDelete`), and the in-page Save button.
- Update active-state checks to `!vm.isEdited && vm.selection == .builtin/.custom` per Component 1.
- Selecting a preset applies it; the page may stay open (dismiss-on-select is a 2B/UX refinement, not required here).

## Component 6 — RootView + app wiring

- `RootView`: owns `@StateObject vm`, `@State showSculpt/showPresets`. Body = `HomeView(vm:onOpenSculpt:{showSculpt=true} onOpenPresets:{showPresets=true} onOpenTimer:{})`, with `.sheet(isPresented:$showSculpt){ SculptSheet(vm: vm) }` and `.fullScreenCover(isPresented:$showPresets){ PresetsView(vm: vm) }`.
- `SculptorApp` roots `RootView()` (keeps `.modelContainer(for: CustomPreset.self)`).
- Delete `RootTabView.swift` (incl. `AppTab`). Rename/replace `NowPlayingView`→`HomeView`, `SculptView`→`SculptSheet`.

## Data Flow

```
Presets button → showPresets=true → fullScreenCover(PresetsView); chevron-back → dismiss
Sculpt button  → showSculpt=true  → sheet(SculptSheet) over dimmed home; grabber/drag → dismiss
chip/preset tap → vm.select/applyCustom → isEdited=false → home header name + active highlight
band drag (sheet) → vm.setGain → isEdited=true (selection kept) → home shows "<name> · EDITED", no chip highlighted
Reset (sheet) → vm.reset() → gains 0, selection .none, isEdited false
Save as preset (sheet) → name alert → modelContext.insert(CustomPreset(...)) → dismiss sheet
```

## Error Handling

- `togglePlay` already surfaces engine errors via `errorText`.
- Save: empty/whitespace name → "Custom"; never persist empty.
- Presenting the Sculpt sheet does not stop playback; dismissing it keeps state.

## Testing

- **PlaybackViewModel:** `isEdited` transitions (select/applyCustom clear; setGain sets + keeps selection); `reset()` zeroes gains + clears selection + isEdited; built-in display-name helper.
- **Presentation/home/sheet/hero:** composition — verified via a build + launch + screenshots of (a) home, (b) Sculpt sheet open, (c) Presets page. (No UI-tap tool: capture home; drive sheets via launch arguments or document that sheet/page screenshots are best-effort + rely on build + VM tests + code review.)
- Swift Testing, pristine output.

## Global Constraints (carried)

- iOS 17.0 floor; Tuist-only generation (no committed `.xcodeproj`/`.xcworkspace`).
- Band frequencies 60/125/250/500/1000/2000/4000/8000 Hz; gain range −24…+12 dB clamped in `setGain`.
- RT-safe render callback untouched.
- Bundle id prefix `com.sculptor`. Dark theme only.
- Font PostScript names `Dock-Lexend-*` via `DockType.font`.
- Swift Testing, pristine output.

## Open Items (deferred)

- 2B: YOUR PRESETS 3-dot menu (Rename / Copy / Delete); Save→opens Presets in rename mode.
- 2C: sleep-timer (moon) auto-stop.
- Stereo width, gentle drift, Dynamic Type, light theme, iCloud sync.
