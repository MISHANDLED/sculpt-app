# Sculptor

An iOS procedural-noise app in the spirit of myNoise: synthesized noise you *sculpt* with an 8-band EQ, then save as your own presets. Built for sleeping, focus, and blocking out the office.

Dark-only, SwiftUI, iOS 17+.

## Features

- **Five built-in noise colors** — White, Pink, Brown, Grey, and Speech Blocker, all synthesized in real time (no audio files) and loudness-normalized against each other.
- **Sculpt sheet** — 8-band EQ sliders to shape the spectrum live while it plays.
- **Custom presets** — save the current sculpt, rename/duplicate/delete/reorder; persisted with SwiftData and restored across launches.
- **Audio-reactive living contours** — a full-screen procedural Metal background driven by the real post-EQ eight-band spectrum, with calm paused drift and reduced Low Power/Reduce Motion profiles.
- **NOISE + PHONE knobs** — circular glow-ring controls for app volume and hardware volume.
- **Sleep timer** — 15/30/45/60 minutes with live countdown and fade-out stop.
- **Plays in the background** — lock-screen Now Playing metadata, remote play/pause, and survives interruptions, route changes (unplugged headphones pause), and media-services resets.

## Requirements

- Xcode 16+ (Swift Testing, swift-tools 6.0)
- [Tuist](https://tuist.dev) 4.x
- iOS 17.0+ simulator or device

## Getting started

```bash
git clone <repo>
cd Noise
tuist generate        # generates Sculptor.xcworkspace (never committed)
```

Open the generated `Sculptor.xcworkspace` and run the `Sculptor` scheme.

## Testing

```bash
Scripts/test-all.sh   # full suite across AudioEngine, DesignSystem, and Sculptor
```

The script exists because the workspace scheme only runs the app's tests — the two local packages test via their own schemes from inside each package directory. See `CLAUDE.md` for the individual invocations.

## Project structure

```
Project.swift               Tuist manifest — Sculptor app + tests only
Packages/
  AudioEngine/              SPM package: noise synthesis, EQ graph, session policy (UI-free)
  DesignSystem/             SPM package: Dock design tokens + components + Lexend fonts
Sculptor/                   App target: SwiftUI views, PlaybackViewModel, SwiftData presets
Scripts/test-all.sh         Full test suite runner
docs/sculptor_design/       Design source of truth (see the Sculptor.dc.html header)
docs/superpowers/           Dated specs and implementation plans
```

The dependency rule: the app imports both packages; the packages import nothing of each other and nothing of the app.
