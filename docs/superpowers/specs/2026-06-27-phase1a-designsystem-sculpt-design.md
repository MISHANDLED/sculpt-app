# Phase 1A — Design System + Sculpt Screen + Audio Hardening

**Date:** 2026-06-27
**Status:** Approved (sections 1–5), ready for implementation planning
**Predecessor:** Phase 0 audio spike (`2026-06-24-phase0-audio-spike-design.md`) — PASSED device-audio gate; synth noise + 8-band EQ confirmed clean.

## Context

Phase 0 proved the audio core (`AudioEngine` framework: `NoiseSource`, `NoisePreset`,
`NoiseEngine`) and shipped a throwaway spike UI (`SpikeViewModel` / `RootView`).

Phase 1 builds the real, designed app per the imported Dock/Blinkit design system
(`sculptor_design/`). The full design has three surfaces — Play/home, Sculpt, Presets —
which is too large for one spec. It is decomposed into three sub-phases, each its own
spec → plan → build → review cycle:

- **Phase 1A (this spec):** `DesignSystem` framework + designed Sculpt screen + audio hardening.
- **Phase 1B:** Play/home screen (big play/pause + live waveform visualizer) + navigation.
- **Phase 1C:** Presets list — built-in + custom preset save/persist, reorder/delete.

Deferred to a later sub-phase (decided during brainstorming): **Stereo width** control and
**Animation / "gentle drift"** toggle (both require new real-time audio-engine work).

## Goals

1. Establish a reusable `DesignSystem` framework carrying the Dock visual language in native SwiftUI.
2. Replace the Phase-0 spike UI with the designed Sculpt screen wired to `NoiseEngine`.
3. Harden `AudioEngine` for real-world playback (explicit format, interruption + route handling).
4. Match the design's 5-chip preset row (White, Pink, Brown, Grey, Speech blocker).

## Non-Goals (Phase 1A)

- Play/home screen and waveform visualizer (Phase 1B).
- Presets list, custom preset persistence (Phase 1C).
- Stereo width, gentle-drift animation (deferred).
- Final-tuned gain tables for Grey / Speech blocker — starter values now, tune by ear later.
- Light theme (app is dark-theme only for v1).

## Architecture

New Tuist framework **`DesignSystem`** (iOS 17, bundle id `com.sculptor.designsystem`).

```
Sculptor (app)  ──▶  DesignSystem   (visual layer: tokens, fonts, components)
       └──────────▶  AudioEngine    (existing audio core)
```

- `DesignSystem` has **no** dependency on `AudioEngine` — it is a pure visual layer and
  knows nothing about audio. Components are dumb views driven by bindings/closures.
- `Sculptor` composes both: a view model binds `DesignSystem` views to `AudioEngine`.

Each unit has one responsibility and a well-defined interface, testable in isolation.

## Component 1 — DesignSystem framework

**Tokens** (semantic, dark-theme values from `colors_and_type.css`):

| Role | Token name | Hex |
|---|---|---|
| Accent | `DockColor.accent` (teal-400) | `#2ED3B7` |
| Background | `DockColor.background` (black-dark) | `#0D0D11` |
| Surface 1 | `DockColor.surface1` (grey-dark-900) | `#17171C` |
| Surface 2 | `DockColor.surface2` (grey-dark-800) | `#202027` |
| Surface 3 | `DockColor.surface3` (grey-dark-700) | `#2F2F37` |
| Text primary | `DockColor.textPrimary` (grey-dark-50) | `#FAFAFA` |
| Text secondary | `DockColor.textSecondary` (grey-dark-300) | `#CACACE` |
| Text tertiary | `DockColor.textTertiary` (grey-dark-400) | `#95959D` |
| Border | `DockColor.border` (grey-dark-700) | `#2F2F37` |

- `DockType` — Lexend `Font` helpers per scale step (sizes 10/12/14/16/18/20/24/28/32/36;
  weights light 300 → bold 700). Map to the design's semantic styles (overline, caption,
  body, h6–h1, display).
- `DockSpacing` (4/8/12/16/24/32…) and `DockRadius` (12/16) constants.
- **Fonts:** bundle the 5 Lexend `.ttf` from `sculptor_design/_ds/.../fonts/` into the
  framework's resources; register at framework load via `CTFontManagerRegisterFontsForURL`
  so consumers need no Info.plist font entries.

**Components** (each its own file, SwiftUI `#Preview` in isolation):

- `BandSlider` — vertical slider, teal fill from baseline, glowing circular knob; bindable
  value + range; emits change via binding. No knowledge of frequency/audio.
- `PresetChip` — pill; unselected = subtle surface + border, selected = teal outline/fill;
  label + tap closure.
- `DockCard` — rounded surface container (radius 16, `surface1`, border) for grouping.
- `DockButton` — primary (teal) / secondary (surface) styles; used for the temporary transport.

## Component 2 — Sculpt screen (`Sculptor` target)

- `SculptViewModel` (`@MainActor`, `ObservableObject`) wraps `NoiseEngine`; **replaces**
  Phase-0 `SpikeViewModel`. Published: `gains: [Float]`, `isPlaying: Bool`,
  `selectedPreset: NoisePreset?` (nil = "custom"), `errorText: String?`.
  Methods: `togglePlay()`, `setGain(band:dB:)`, `select(preset:)`.
- `SculptView` layout (per `sculptor_design/screenshots/lower.png`):
  - `DockCard` holding 8 vertical `BandSlider`s with horizontal grid lines and freq labels
    (60 / 125 / 250 / 500 / 1k / 2k / 4k / 8k).
  - Horizontal scrollable `PresetChip` row: White, Pink, Brown, Grey, Speech blocker.
  - **Temporary** play/pause (`DockButton`) — scaffolding so EQ changes are audible; removed
    when Phase 1B's home screen provides the real transport. Flagged as scaffolding, not a
    design surface.
- Interactions:
  - Tap chip → `vm.select(preset)` → `NoiseEngine.apply(preset)`; sliders animate to preset
    gains; chip shows selected.
  - Drag a slider → `vm.setGain` → clears `selectedPreset` (state becomes "custom"),
    deselecting the active chip.
- Phase-0 `RootView` is removed; `SculptorApp` roots `SculptView`.

## Component 3 — Audio hardening (`AudioEngine`)

1. **Explicit format.** Build the graph from an explicit
   `AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)` (float32, non-interleaved)
   instead of `engine.outputNode.inputFormat(forBus: 0)` read at `init()` (unreliable before
   the session is active). Connect sourceNode → eq → mainMixer with this format.
2. **Interruption handling.** Observe `AVAudioSession.interruptionNotification`:
   - `.began` → stop engine, set `isPlaying = false`.
   - `.ended` with `options.contains(.shouldResume)` → restart if it was playing.
3. **Route change.** Observe `AVAudioSession.routeChangeNotification`:
   - `.oldDeviceUnavailable` (e.g. headphones unplugged) → pause, so audio never blasts the
     built-in speaker unexpectedly.
4. **New presets** (starter tables — tune by ear later):
   - `NoisePreset.grey` — equal-loudness-shaped tilt: gentle boost at low + high band edges,
     dip through 500–2000 Hz, approximating an inverse equal-loudness contour.
   - `NoisePreset.speechBlocker` — boost the 250/500/1000/2000 Hz bands (speech intelligibility
     range ~300–3000 Hz), flat/attenuated elsewhere, to mask nearby conversation.
   - Both clamp to the existing gain range (−24…+12 dB) via `setGain`.

Notification observers live on the main actor; the render callback stays RT-safe and untouched
(no locks/alloc/ARC on the audio thread).

## Data Flow

```
PresetChip tap ─▶ SculptViewModel.select(preset)
                     ├─▶ NoiseEngine.apply(preset)        (EQ band gains set, clamped)
                     └─▶ @Published gains updated          (sliders animate)

BandSlider drag ─▶ SculptViewModel.setGain(band, dB)
                     ├─▶ NoiseEngine.setGain(band, dB)
                     └─▶ selectedPreset = nil              (chip deselects → "custom")

AVAudioSession interruption/route ─▶ NoiseEngine observer ─▶ stop/resume + isPlaying
```

## Error Handling

- `NoiseEngine.start()` already `throws`; `SculptViewModel` catches and surfaces via
  `errorText`. Interruption/route observers update `isPlaying` so UI stays in sync.
- Font registration failures are logged (non-fatal); SwiftUI falls back to system font.

## Testing

- **DesignSystem:** font registration succeeds (Lexend resolvable post-load); token values
  match the table; pure component logic (e.g. `BandSlider` fill fraction from value/range).
- **AudioEngine:** `grey` / `speechBlocker` gain tables have expected shape and are clamped to
  −24…+12; graph builds with the explicit format; interruption/route handlers produce the
  correct `isPlaying` transitions when fed synthetic notifications (handler logic extracted so
  it is unit-testable without a live session).
- **Sculpt VM:** `select(preset)` updates `gains` to the preset's table; `setGain` clears
  `selectedPreset`; `togglePlay` flips `isPlaying`.
- All via Swift Testing (`import Testing`, `@Test`, `#expect`). Test output pristine.

## Global Constraints (carried from Phase 0)

- iOS 17.0 floor; Tuist-only project generation (no hand-edited `.xcodeproj`).
- Band frequencies: 60 / 125 / 250 / 500 / 1000 / 2000 / 4000 / 8000 Hz.
- Gain range: −24 … +12 dB, clamped in `NoiseEngine.setGain`.
- RT-safe render callback (no locks/heap-alloc/ARC/self-capture on the audio thread).
- Bundle id prefix `com.sculptor` (`com.sculptor.designsystem` for the new framework).
- Dark theme only.

## Open Items (deferred, not blocking 1A)

- Final-tuned Grey / Speech-blocker gain tables (tune by ear after build).
- Stereo width + gentle-drift animation (later sub-phase).
- Play/home screen + visualizer (Phase 1B); Presets persistence (Phase 1C).
