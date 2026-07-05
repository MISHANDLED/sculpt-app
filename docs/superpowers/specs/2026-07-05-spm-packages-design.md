# Local SPM Packages + Free-Function Elimination — Design

**Date:** 2026-07-05
**Status:** Approved

## Goal

Convert the AudioEngine and DesignSystem Tuist framework targets into local Swift
Package Manager packages, and eliminate all top-level free functions in favor of
static methods on caseless enums. Tuist stays as the project generator; the
Sculptor app remains a Tuist target that consumes the local packages.

## Current State

- Tuist 4.201.0 project (`Project.swift`) with five targets: AudioEngine
  (framework), DesignSystem (framework, bundles Lexend fonts), Sculptor (app),
  plus a unit-test target per module.
- 14 top-level free functions:
  - AudioEngine (4): `downsample`, `fadeCurve`, `interruptionAction`,
    `routeChangeAction`
  - DesignSystem (4): `miniEQBarHeight`, `scopeY`, `bandSliderFillFraction`,
    `dockRGB` (internal)
  - Sculptor (6): `bandsRaisedCount`, `copyName`, `sanitizedRename`,
    `selectionToken`, `parseSelectionToken`, `formatCountdown`
- `FontRegistrar` already loads fonts through `Bundle.module`, which SPM
  provides natively — no font-loading code changes needed.
- `AudioSessionPolicy` uses `AVAudioSession` (iOS-only), so packages cannot run
  `swift test` on macOS; tests run via xcodebuild against an iOS simulator.

## Decisions

1. **Keep Tuist.** Packages are wired in with Tuist's native local-package
   support: `packages: [.package(path: "Packages/…")]` on the Project and
   `.package(product: "…")` dependencies on the app target. No `tuist install`
   step (that route is for remote dependencies).
2. **Caseless enums for namespacing.** Matches the existing `KnobGeometry` and
   `FontRegistrar` pattern already in the codebase.
3. **Conversion applies to all three modules**, not just the packages.
4. **Tier-1 cleanup rides along** as a separate first commit: delete the
   `WhiteNoise/` Phase-0 spike, `Focus app with white noise.zip`, unused
   `DockButton.swift`, and placeholder `DesignSystem/Tests/SmokeTests.swift`.

## Target Layout

```
Packages/
  AudioEngine/
    Package.swift              # swift-tools-version 6.0, platforms: [.iOS(.v17)]
    Sources/AudioEngine/       # 7 source files, moved as-is
    Tests/AudioEngineTests/    # 13 test files
  DesignSystem/
    Package.swift
    Sources/DesignSystem/      # Components/ Fonts/ Tokens/
    Sources/DesignSystem/Resources/Fonts/   # 5 Lexend .ttf, resources: [.process(...)]
    Tests/DesignSystemTests/
Project.swift                  # Sculptor app + SculptorTests targets only
```

## Function → Enum Mapping

| Current free function | New API |
|---|---|
| `downsample(_:to:)` | `Downsample.resample(_:to:)` |
| `fadeCurve(from:steps:)` | `Fade.curve(from:steps:)` |
| `interruptionAction(type:options:isPlaying:)` | `AudioSessionPolicy.interruptionAction(type:options:isPlaying:)` |
| `routeChangeAction(reason:)` | `AudioSessionPolicy.routeChangeAction(reason:)` |
| `miniEQBarHeight(gain:range:maxHeight:)` | `MiniEQGeometry.barHeight(gain:range:maxHeight:)` |
| `scopeY(value:height:)` | `ScopeGeometry.y(value:height:)` |
| `bandSliderFillFraction(value:in:)` | `SliderGeometry.fillFraction(value:in:)` |
| `dockRGB(hex:)` (internal) | `DockColorHex.rgb(hex:)` (internal) |
| `bandsRaisedCount(_:)` | `PresetMetrics.bandsRaisedCount(_:)` |
| `copyName(of:)` | `PresetMetrics.copyName(of:)` |
| `sanitizedRename(old:new:)` | `PresetMetrics.sanitizedRename(old:new:)` |
| `selectionToken(_:)` | `SelectionPersistence.token(_:)` |
| `parseSelectionToken(_:)` | `SelectionPersistence.parse(_:)` |
| `formatCountdown(_:)` | `SleepFormatting.countdown(_:)` |

All call sites and tests update accordingly. Enums are caseless
(`public enum Fade { public static func curve(...) }`) so they cannot be
instantiated.

## Testing Strategy

- Package test directories move inside their packages
  (`Tests/AudioEngineTests`, `Tests/DesignSystemTests`).
- All tests continue to run through xcodebuild with an iOS-simulator
  destination; the generated workspace exposes auto-created package schemes.
- No macOS `swift test` support (blocked by `AVAudioSession`); current workflow
  is simulator-based anyway.
- Success bar: every existing test passes after each commit; app builds and
  runs on simulator with fonts rendering (Lexend) and audio playing.

## Sequence (3 commits)

1. **Cleanup** — delete `WhiteNoise/`, the reference zip, `DockButton.swift`,
   `SmokeTests.swift`.
2. **Package restructure** — create `Packages/AudioEngine` and
   `Packages/DesignSystem` with Package.swift manifests, `git mv` sources and
   tests, move fonts under `Sources/DesignSystem/Resources/Fonts/`, rewrite
   `Project.swift` to two targets + local packages, `tuist generate`, build and
   test green.
3. **Function → enum conversion** — apply the mapping table across sources,
   call sites, and tests; build and test green.

## Risks

- Tuist local-package integration edge cases around resource processing.
  Mitigation: `Bundle.module` is already the access path; if `.process` mangles
  the .ttf files, fall back to `.copy`.
- Verification includes launching the app in the simulator to confirm fonts
  register and audio plays (not just unit tests).

## Out of Scope

- Moving app-level code (viewmodels, views) into packages.
- `Noise_Sculptor_v1_Plan.pdf` and `sculptor_design/` pruning (Tier 2 —
  undecided).
- Any behavior changes; this is structure-only.
