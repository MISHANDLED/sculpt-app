# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Sculptor — iOS procedural-noise app (myNoise-style): synthesized white/pink/brown/grey/speech-blocker noise shaped by an 8-band EQ, with savable custom presets, sleep timer, and lock-screen Now Playing. iOS 17+, dark-only, SwiftUI, Swift Testing. Tuist-generated project consuming two local SPM packages.

## Commands

```bash
tuist generate --no-open      # regenerate Sculptor.xcworkspace after ANY Project.swift/package structure change

Scripts/test-all.sh           # FULL test suite across all three schemes

# app tests — from repo root
xcodebuild test -workspace Sculptor.xcworkspace -scheme Sculptor-Workspace -destination "platform=iOS Simulator,name=iPhone 16"

# package tests — from inside each package directory
cd Packages/AudioEngine  && xcodebuild test -scheme AudioEngine  -destination "platform=iOS Simulator,name=iPhone 16"
cd Packages/DesignSystem && xcodebuild test -scheme DesignSystem -destination "platform=iOS Simulator,name=iPhone 16"

# single test file
xcodebuild test ... -only-testing:AudioEngineTests/SpectrumFFTTests
```

A green `Sculptor-Workspace` run alone is NOT "tests pass" — it silently skips both package suites.

xcodebuild gotchas:
- Output buffers: never pipe xcodebuild to grep (looks like a hang). Redirect to a log file, then inspect it.
- Swift Testing runs `@Test`s in parallel; `-only-testing` can mask cross-test interactions. Trust only the full scheme suite.
- SourceKit/editor diagnostics here are chronically false ("No such module 'Testing'", "AVAudioSession unavailable in macOS", macOS-availability errors on SwiftUI). Only xcodebuild results count.

Run the app: build the `Sculptor` scheme, then `xcrun simctl install/launch booted com.mishandled.sculptor` (bundle id).

## Architecture

Three modules, strict dependency direction: `Sculptor (app) → Packages/AudioEngine + Packages/DesignSystem` (packages don't know each other or the app).

**Packages/AudioEngine** — the defensible UI-free core.
- `NoiseEngine` owns `AVAudioSourceNode (synth noise) → 8-band AVAudioUnitEQ → mainMixer`, post-EQ spectrum capture/analysis, fade-out, interruption/route/media-reset recovery, and the background-audio session. Control state is `@MainActor`; the render callback uses only preallocated source state and a raw spectrum submission handle.
- `SpectrumMailbox` uses the local `RealtimeAtomics` C11 target for iOS 17-compatible lock-free slot transitions. `SpectrumAnalyzer` polls the newest complete frame and reuses `SpectrumFFT`/Accelerate storage.
- Pure decision logic remains in caseless enums: `AudioSessionPolicy`, `Fade`, and `NoisePreset`.

**Packages/DesignSystem** — Dock/Blinkit visual layer, app-agnostic components.
- `Tokens/` provides `DockColor`, `DockType`, and `DockMetrics`; `Components/` provides `PlayHeroButton`, `VolumeKnob`/`KnobGeometry`, `BandSlider`, `MiniEQIcon`, `PresetRow`, `PresetChip`, and `DockCard`.
- Lexend fonts are SPM resources. Their filenames are `Lexend-*`, but internal PostScript names are `Dock-Lexend-*`; `Font.custom`/`UIFont(name:)` must use the internal names and `FontRegistrar.registerFonts()` must run at app start.
- View geometry remains in caseless enums such as `SliderGeometry` and `MiniEQGeometry`.

**Sculptor (app)** — SwiftUI shell, no tab bar.
- `RootView` owns one `PlaybackViewModel` and navigation state. Home renders `RippleBackground` behind its controls; Sculpt is an opaque sheet that leaves the uncovered Home effect active; Presets is a full-screen cover that disables analysis/rendering.
- `PlaybackViewModel` coordinates gains, `PresetSelection`, edits, sleep timer, master volume, finite spectrum targets/timestamps, Home visibility, Now Playing, and Save→rename handoff.
- `RippleAnimationState` provides deterministic attack/release/stale decay. `RippleBackground` binds its uniforms to app-target `LivingContours.metal`.
- SwiftData persists `CustomPreset`; `SelectionPersistence` stores the active selection. `SystemVolume` bridges `AVAudioSession.outputVolume` and a hidden `MPVolumeView` for the PHONE knob.

## Conventions

- **No top-level Swift free functions.** Standalone Swift logic uses static methods on caseless enums. C ABI exceptions: the prefixed `rt_atomic_u8_*` functions in the private C11 shim, and the `@_cdecl("rt_spectrum_mailbox_submit")` entry in `SpectrumMailbox.swift` (`@_cdecl` requires a global func; `Scripts/audit-realtime-linkage.sh` checks the symbol).
- Structure changes (new files, targets, resources): edit `Project.swift` or the relevant `Packages/*/Package.swift`, then `tuist generate`. Never hand-edit generated `.xcworkspace`/`Derived/`.
- Package manifests: swift-tools-version 6.0, `platforms: [.iOS(.v17)]`, `swiftLanguageModes: [.v5]`.
- Trunk-based: commit directly on `master`, no feature branches. Remote: `origin` = github.com/MISHANDLED/sculpt-app via the `github.com-mishandled` SSH alias. Commit identity is repo-local git config (`MISHANDLED <52106838+MISHANDLED@users.noreply.github.com>`) — plain `git commit` uses it; never add Co-Authored-By trailers (repo must show a single contributor).
- Design source of truth: the descriptive header inside `docs/sculptor_design/Sculptor.dc.html` (~line 33) — NOT the screenshots, and NOT `Controls Explorations.dc.html`/`tabbars.png` (those are explorations; a 3-tab UI built from them was wrong and got reworked). Read the header before changing navigation/IA.
- Specs in `docs/superpowers/specs/`, plans in `docs/superpowers/plans/` (dated files); progress ledger at `.superpowers/sdd/progress.md` (git-ignored).
