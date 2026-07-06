# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Sculptor — iOS procedural-noise app (myNoise-style): synthesized white/pink/brown/grey/speech-blocker noise shaped by an 8-band EQ, with savable custom presets, sleep timer, and lock-screen Now Playing. iOS 17+, dark-only, SwiftUI, Swift Testing. Tuist-generated project consuming two local SPM packages.

## Commands

```bash
tuist generate --no-open      # regenerate Sculptor.xcworkspace after ANY Project.swift/package structure change

Scripts/test-all.sh           # FULL test suite (119 tests) — the only "full suite" command
```

Full suite is **three** xcodebuild invocations (the script wraps them). Local-package schemes are invisible to `-workspace`; each package tests from inside its own directory:

```bash
# app tests only (45) — from repo root
xcodebuild test -workspace Sculptor.xcworkspace -scheme Sculptor-Workspace -destination "platform=iOS Simulator,name=iPhone 16"

# package tests — from inside the package dir
cd Packages/AudioEngine  && xcodebuild test -scheme AudioEngine  -destination "platform=iOS Simulator,name=iPhone 16"   # 51
cd Packages/DesignSystem && xcodebuild test -scheme DesignSystem -destination "platform=iOS Simulator,name=iPhone 16"   # 23

# single test file
xcodebuild test ... -only-testing:AudioEngineTests/DownsampleTests
```

A green `Sculptor-Workspace` run alone is NOT "tests pass" — it silently skips the 74 package tests.

xcodebuild gotchas:
- Output buffers: never pipe xcodebuild to grep (looks like a hang). Redirect to a log file, then inspect it.
- Swift Testing runs `@Test`s in parallel; `-only-testing` can mask cross-test interactions. Trust only the full scheme suite.
- SourceKit/editor diagnostics here are chronically false ("No such module 'Testing'", "AVAudioSession unavailable in macOS", macOS-availability errors on SwiftUI). Only xcodebuild results count.

Run the app: build the `Sculptor` scheme, then `xcrun simctl install/launch booted com.mishandled.sculptor` (bundle id).

## Architecture

Three modules, strict dependency direction: `Sculptor (app) → Packages/AudioEngine + Packages/DesignSystem` (packages don't know each other or the app).

**Packages/AudioEngine** — the defensible core, UI-free.
- `NoiseEngine` (public final class): owns the AVAudioEngine graph `AVAudioSourceNode (synth noise) → 8-band AVAudioUnitEQ → mainMixer`. Also: scope tap on EQ output (downsampled to 128 pts via `onScopeSamples` callback), fade-out on stop, interruption/route-change/media-services-reset recovery, background-audio session. Threading: RT audio callback fills buffers; state mutations hop to `@MainActor`.
- Pure decision logic lives in caseless enums so it's unit-testable without audio hardware: `AudioSessionPolicy` (interruption/route actions), `Fade.curve`, `Downsample.resample`, `NoisePreset` (5 builtin presets + per-preset gain tables + loudness-normalizing global gain).

**Packages/DesignSystem** — Dock/Blinkit visual layer, app-agnostic components.
- `Tokens/` (DockColor teal #2ED3B7 accent, DockType, DockMetrics), `Components/` (PlayHeroButton, VolumeKnob + KnobGeometry, BandSlider, ScopeVisualizer, MiniEQIcon, PresetRow, PresetChip, DockCard).
- Bundles Lexend fonts as SPM resources (`Bundle.module`). **Trap:** `.ttf` FILENAMES are `Lexend-*` but the fonts' internal PostScript names are `Dock-Lexend-*` — `Font.custom`/`UIFont(name:)` must use `Dock-Lexend-*` or you silently get system font. `FontRegistrar.registerFonts()` must run at app start.
- View-geometry math is in caseless enums beside each component (`ScopeGeometry`, `SliderGeometry`, `MiniEQGeometry`) so it tests without rendering.

**Sculptor (app)** — SwiftUI shell, no tab bar.
- `RootView` owns the single `PlaybackViewModel` (`@StateObject`, injected everywhere as `@ObservedObject`) plus navigation state. Home (`HomeView`) = hero play button + scope + NOISE/PHONE knobs + preset chip rail; Sculpt = sheet (`SculptSheet`); Presets = fullScreenCover (`PresetsView`).
- `PlaybackViewModel` is the coordination hub: gains, `PresetSelection` (none/builtin/custom enum), isEdited, sleep timer (1 Hz tick + deadline), master volume, scope samples, Save→rename handoff (`presetToRename`). Cross-view coordination goes through @Published VM state, NOT callback closures.
- Persistence: SwiftData `@Model CustomPreset` (container at app root); active selection persists via `SelectionPersistence.token/parse` string tokens.
- `SystemVolume`: KVO bridge to `AVAudioSession.outputVolume` + hidden `MPVolumeView` slider for setting hardware volume (PHONE knob).

## Conventions

- **No top-level free functions.** All standalone logic = static methods on caseless enums (`enum Foo { static func bar(...) }`). Enforced repo-wide; keep it that way.
- Structure changes (new files, targets, resources): edit `Project.swift` or the relevant `Packages/*/Package.swift`, then `tuist generate`. Never hand-edit generated `.xcworkspace`/`Derived/`.
- Package manifests: swift-tools-version 6.0, `platforms: [.iOS(.v17)]`, `swiftLanguageModes: [.v5]`.
- Trunk-based: commit directly on `master`, no remote, no feature branches. Commit identity: `git -c user.name='Sculptor' -c user.email='dev@sculptor.local' commit ...`
- Design source of truth: the descriptive header inside `docs/sculptor_design/Sculptor.dc.html` (~line 33) — NOT the screenshots, and NOT `Controls Explorations.dc.html`/`tabbars.png` (those are explorations; a 3-tab UI built from them was wrong and got reworked). Read the header before changing navigation/IA.
- Specs in `docs/superpowers/specs/`, plans in `docs/superpowers/plans/` (dated files); progress ledger at `.superpowers/sdd/progress.md` (git-ignored).
