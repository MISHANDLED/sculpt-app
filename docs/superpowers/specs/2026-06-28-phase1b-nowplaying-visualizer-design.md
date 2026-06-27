# Phase 1B — Tab Shell + Now Playing Screen + Scope Visualizer

**Date:** 2026-06-28
**Status:** Approved (sections 1–6), ready for implementation planning
**Predecessors:** Phase 0 (audio core, device-gate passed), Phase 1A (`2026-06-27-phase1a-designsystem-sculpt-design.md` — DesignSystem framework + Sculpt screen + audio hardening).

## Context

Phase 1A shipped the `DesignSystem` framework and the designed Sculpt screen, rooted standalone in `SculptorApp`. The full design is a **3-tab app** (per `sculptor_design/screenshots/tabbars.png`): **Now Playing**, **Sculpt**, **Presets**.

Phase 1B builds the tab shell, the Now Playing screen (the play/pause hero + an oscilloscope-style "Scope" waveform visualizer driven by a real audio tap), and hoists shared playback state so all tabs stay in sync. The Presets tab is added as a placeholder, filled in Phase 1C.

## Goals

1. Wrap the app in a 3-tab shell (Now Playing / Sculpt / Presets) matching the design.
2. Build the Now Playing screen: large play/pause hero, scope visualizer, status text, shared preset-chip row.
3. Add a real audio tap on the engine that feeds a downsampled sample window to the UI, and a `ScopeVisualizer` component that draws a glowing oscilloscope line from it.
4. Hoist the playback model so Now Playing and Sculpt share one source of truth.

## Non-Goals (Phase 1B)

- Presets list content, custom preset save/persist (Phase 1C — the Presets tab is a placeholder this phase).
- FFT/spectrum-bar visualizer (the chosen style is the time-domain oscilloscope "Scope"; no FFT).
- The Sculpt-screen bottom transport row from the design (entangled with save-preset [1C] and a theme toggle [we are dark-only]); deferred to a later polish pass.
- Stereo width, gentle-drift animation (still deferred from 1A).
- Light theme, Dynamic Type (still dark-only; Dynamic Type deferred).

## Architecture

```
SculptorApp
  └─ RootTabView            owns ONE PlaybackViewModel (@StateObject), injects into tabs
       ├─ NowPlayingView    (@ObservedObject vm) — hero transport + ScopeVisualizer + chips
       ├─ SculptView        (@ObservedObject vm) — EQ sliders + chips  (temp transport removed)
       └─ PresetsPlaceholderView                  — "coming in 1C"
```

- **Rename `SculptViewModel` → `PlaybackViewModel`** (and `SculptViewModelTests` → `PlaybackViewModelTests`). It now backs all tabs: play state, gains, selected preset, and scope samples. It is no longer Sculpt-specific; the rename keeps the name honest. All Phase-1A references updated.
- The shared model is created once in `RootTabView` as `@StateObject` and passed to each tab view as an `@ObservedObject` init parameter. Tabs must NOT each create their own `@StateObject`, or state desyncs.
- DesignSystem stays a pure visual layer (no AudioEngine dependency); the new `ScopeVisualizer` is a dumb component taking a sample array.

## Component 1 — Tab shell (`Sculptor` target)

- `RootTabView` — `TabView` with three tabs. A `Tab` enum (`nowPlaying`, `sculpt`, `presets`) drives selection; each tab has an SF Symbol + Lexend label:
  - Now Playing — `play.circle`
  - Sculpt — `slider.vertical.3`
  - Presets — `bookmark`
- `SculptorApp` roots `RootTabView()` (replaces the direct `SculptView()`).
- Tab bar tint uses `DockColor.accent`; dark background.

## Component 2 — Now Playing screen (`Sculptor` target)

- `NowPlayingView(vm:)` (`@ObservedObject`):
  - **Play/pause hero:** large circular button, teal fill + glow ring (per `tabbars.png`), shows pause glyph when playing / play glyph when paused; tap → `vm.togglePlay()`.
  - **`ScopeVisualizer(samples:)`** below the hero.
  - **Status text:** "Playing · tap to pause" when playing, "Paused" otherwise (`DockType`, tertiary color).
  - **Preset chip row:** the shared `PresetChipsRow` (see Component 5).
- Hero button extracted as a DesignSystem component `PlayHeroButton(isPlaying:action:)` (dumb, reusable).

## Component 3 — Audio tap + scope samples (`AudioEngine`)

- `NoiseEngine`:
  - `var onScopeSamples: (([Float]) -> Void)?` — invoked on the main queue with a downsampled window (~128 floats, mono mix) of recent output.
  - On `start()`: install an `AVAudioNodeTap` on the EQ output node (`bufferSize` ~4096, the engine's `outputFormat`). In the tap callback (a non-render background thread): read channel 0, call the pure `downsample(_:to:)` to ~128 points, then `DispatchQueue.main.async` invoke `onScopeSamples`. On `stop()`: `removeTap(onBus:)`.
  - The render callback is NOT touched; RT-safety preserved (the tap is a separate, non-realtime callback — it must still avoid blocking, which copying + a downsample satisfies).
- Pure helper `func downsample(_ samples: [Float], to count: Int) -> [Float]` — block-average the input into exactly `count` contiguous blocks (mean of each block), producing `count` points (`count` clamped ≥ 1; empty input → empty; input shorter than `count` → returns the input unchanged). Unit-tested.

## Component 4 — ScopeVisualizer (`DesignSystem`)

- `ScopeVisualizer(samples: [Float])` — a SwiftUI `Canvas` drawing a single glowing teal polyline across the width, mapping each sample to a Y position around the vertical center. Empty/all-zero samples → flat center line (paused look). Glow via a blurred stroke under the crisp stroke, `DockColor.accent`.
- Pure helper `func scopeY(value: Float, height: CGFloat) -> CGFloat` mapping a sample (assumed roughly −1...1, clamped) to a Y where 0 → vertical center, +1 → top, −1 → bottom; unit-tested. The view is otherwise dumb and previewable.

## Component 5 — Shared preset-chip row (`Sculptor` target)

- `PresetChipsRow(vm:)` — horizontal `ScrollView` of `PresetChip`s for the five presets (White/Pink/Brown/Grey/Speech blocker), selected state from `vm.selectedPreset`, tap → `vm.select(_:)`. Used by both `NowPlayingView` and `SculptView` (extracted from the inline row currently in `SculptView`).

## Component 6 — Presets placeholder (`Sculptor` target)

- `PresetsPlaceholderView` — centered Dock-styled message ("Your presets" + "Coming soon"), dark background. Replaced by the real list in 1C.

## Data Flow

```
play/pause hero tap ─▶ PlaybackViewModel.togglePlay() ─▶ NoiseEngine.start()/stop()
NoiseEngine.start() ─▶ installs tap ─▶ tap callback (bg thread):
    downsample(channel0, to: 128) ─▶ DispatchQueue.main.async ─▶ onScopeSamples(window)
        ─▶ PlaybackViewModel.scopeSamples (@Published) ─▶ ScopeVisualizer redraws
NoiseEngine.stop() ─▶ removes tap ─▶ scopeSamples cleared ─▶ flat line
chip tap (either tab) ─▶ vm.select(preset) ─▶ shared state ─▶ both tabs reflect it
```

## Error Handling

- `togglePlay()` already surfaces `start()` errors via `errorText`. Tap installation failures are caught/logged and leave the scope flat (non-fatal — audio still plays).
- Stopping clears `scopeSamples` so the visualizer doesn't freeze on a stale frame.

## Testing

- **AudioEngine:** `downsample(_:to:)` — correct output length, averaging/stride behavior, empty-input and count=1 edge cases. Tap lifecycle (installed after `start`, removed after `stop`) verified via a flag/state seam without asserting on live audio.
- **DesignSystem:** `scopeY`/`scopePoint` mapping — center for 0, clamped for out-of-range, monotonic within range.
- **PlaybackViewModel:** rename keeps existing select/setGain/selectedPreset tests green; `onScopeSamples` callback updates `scopeSamples`; `stop` clears it.
- **Tab shell:** `Tab` enum cases/labels; `RootTabView` builds.
- Swift Testing, pristine output.

## Global Constraints (carried)

- iOS 17.0 floor; Tuist-only generation (no committed `.xcodeproj`/`.xcworkspace`).
- Band frequencies 60/125/250/500/1000/2000/4000/8000 Hz; gain range −24…+12 dB clamped in `setGain`.
- RT-safe render callback untouched (no locks/alloc/ARC/self-capture on the audio thread).
- Bundle id prefix `com.sculptor`.
- Dark theme only.
- Font PostScript names are `Dock-Lexend-*` (NOT `Lexend-*`); `.ttf` filenames are `Lexend-*` — keep the split.
- Swift Testing, pristine output.

## Open Items (deferred, not blocking 1B)

- Presets list + custom preset persistence (Phase 1C).
- Sculpt-screen bottom transport row, theme toggle, save-preset bookmark (later / 1C / dark-only).
- Stereo width, gentle-drift animation; Dynamic Type; spectrum-bar visualizer variant.
