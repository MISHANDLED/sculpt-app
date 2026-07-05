# Local SPM Packages + Free-Function Elimination Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert AudioEngine and DesignSystem from Tuist framework targets into local SPM packages under `Packages/`, and replace all 14 top-level free functions with static methods on caseless enums.

**Architecture:** Tuist stays as project generator. `Project.swift` keeps only the Sculptor app + SculptorTests targets and pulls the two packages in via `packages: [.package(path:)]` + `.package(product:)` dependencies. Package tests move inside the packages and run through xcodebuild package schemes against an iOS simulator. Spec: `docs/superpowers/specs/2026-07-05-spm-packages-design.md`.

**Tech Stack:** Tuist 4.201.0, Swift Package Manager (swift-tools-version 6.0, `swiftLanguageModes: [.v5]`), Swift Testing, xcodebuild + iOS simulator.

## Global Constraints

- Structure-only refactor: NO behavior changes. Function bodies move verbatim unless a task shows otherwise.
- Deployment floor iOS 17.0 everywhere (`platforms: [.iOS(.v17)]` in manifests).
- Package manifests: `// swift-tools-version: 6.0` with `swiftLanguageModes: [.v5]` (keeps current Swift-5 language mode; avoids new strict-concurrency errors).
- Namespaces are **caseless enums** with `static func` members. Never structs or classes.
- Commits on `master` (trunk, no branches) with identity: `git -c user.name='Sculptor' -c user.email='dev@sculptor.local' commit ...`
- **Full-suite rule:** Swift Testing runs `@Test`s in parallel; a green isolated run can hide cross-test failures. Always finish a task with the full schemes listed in that task.
- **xcodebuild buffering:** never pipe xcodebuild to grep directly — it looks like a hang. Redirect to a log file, then inspect: `xcodebuild ... > /tmp/t.log 2>&1; tail -30 /tmp/t.log`.
- Simulator: pick the first available iPhone once and reuse: `xcrun simctl list devices available | grep -m1 -o 'iPhone [^(]*' | head -1` (call it `{SIM}` below; e.g. `iPhone 16`).
- Before Task 1, capture the baseline: run the full suite on scheme `Sculptor-Workspace` and record the total test count (120 expected as of 2026-07-05). Every later task must end with the same count (minus the 1 test deleted in Task 1).
- SourceKit/editor diagnostics ("No such module 'Testing'", "Bundle has no member 'module'") are false positives here; only xcodebuild results count.

---

### Task 1: Tier-1 cleanup (dead weight)

**Files:**
- Delete: `WhiteNoise/` (entire directory, 9 tracked files — Phase-0 UIKit spike, not referenced in `Project.swift`)
- Delete: `Focus app with white noise.zip`
- Delete: `DesignSystem/Sources/Components/DockButton.swift` (zero references outside itself)
- Delete: `DesignSystem/Tests/SmokeTests.swift` (placeholder `#expect(Bool(true))`)

**Interfaces:**
- Consumes: nothing.
- Produces: clean tree for the package moves; total test count drops by exactly 1 (the smoke test).

- [ ] **Step 1: Verify deletions are safe**

Run:
```bash
grep -rn "DockButton" Sculptor DesignSystem AudioEngine --include="*.swift" | grep -v "Sources/Components/DockButton.swift"
grep -rn "WhiteNoise" Project.swift Tuist.swift
```
Expected: no output from either command.

- [ ] **Step 2: Delete**

```bash
git rm -r WhiteNoise "Focus app with white noise.zip" \
  DesignSystem/Sources/Components/DockButton.swift \
  DesignSystem/Tests/SmokeTests.swift
```

- [ ] **Step 3: Regenerate and run full suite**

```bash
tuist generate --no-open
xcodebuild test -workspace Sculptor.xcworkspace -scheme Sculptor-Workspace \
  -destination "platform=iOS Simulator,name={SIM}" > /tmp/task1-tests.log 2>&1
tail -30 /tmp/task1-tests.log
```
Expected: `** TEST SUCCEEDED **`, total = baseline − 1.

- [ ] **Step 4: Commit**

```bash
git -c user.name='Sculptor' -c user.email='dev@sculptor.local' commit \
  -m "chore: delete Phase-0 spike, reference zip, unused DockButton, placeholder smoke test"
```

---

### Task 2: AudioEngine → local SPM package

**Files:**
- Create: `Packages/AudioEngine/Package.swift`
- Move: `AudioEngine/Sources/*.swift` → `Packages/AudioEngine/Sources/AudioEngine/` (7 files)
- Move: `AudioEngine/Tests/*.swift` → `Packages/AudioEngine/Tests/AudioEngineTests/` (12 files)
- Modify: `Project.swift` (remove AudioEngine + AudioEngineTests targets; add `packages:`; app depends on `.package(product: "AudioEngine")`)

**Interfaces:**
- Consumes: nothing.
- Produces: `import AudioEngine` keeps working unchanged for Sculptor sources and DesignSystem-era call sites; package scheme `AudioEngine` runs AudioEngineTests.

- [ ] **Step 1: Move sources and tests**

```bash
mkdir -p Packages/AudioEngine/Sources/AudioEngine Packages/AudioEngine/Tests/AudioEngineTests
git mv AudioEngine/Sources/*.swift Packages/AudioEngine/Sources/AudioEngine/
git mv AudioEngine/Tests/*.swift Packages/AudioEngine/Tests/AudioEngineTests/
rmdir AudioEngine/Sources AudioEngine/Tests AudioEngine
```

- [ ] **Step 2: Write the manifest**

Create `Packages/AudioEngine/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AudioEngine",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "AudioEngine", targets: ["AudioEngine"])
    ],
    targets: [
        .target(name: "AudioEngine"),
        .testTarget(name: "AudioEngineTests", dependencies: ["AudioEngine"])
    ],
    swiftLanguageModes: [.v5]
)
```

- [ ] **Step 3: Rewrite Project.swift**

Replace the whole file with (DesignSystem targets stay for now — they move in Task 3):

```swift
import ProjectDescription

let project = Project(
    name: "Sculptor",
    packages: [
        .package(path: "Packages/AudioEngine")
    ],
    targets: [
        .target(
            name: "DesignSystem",
            destinations: .iOS,
            product: .framework,
            bundleId: "com.mishandled.sculptor.designsystem",
            deploymentTargets: .iOS("17.0"),
            sources: ["DesignSystem/Sources/**"],
            resources: ["DesignSystem/Resources/**"],
            dependencies: []
        ),
        .target(
            name: "DesignSystemTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.mishandled.sculptor.designsystem.tests",
            deploymentTargets: .iOS("17.0"),
            sources: ["DesignSystem/Tests/**"],
            dependencies: [.target(name: "DesignSystem")]
        ),
        .target(
            name: "Sculptor",
            destinations: .iOS,
            product: .app,
            bundleId: "com.mishandled.sculptor",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .extendingDefault(with: [
                "UILaunchScreen": [:],
                "UIBackgroundModes": ["audio"]
            ]),
            sources: ["Sculptor/Sources/**"],
            dependencies: [
                .package(product: "AudioEngine"),
                .target(name: "DesignSystem")
            ]
        ),
        .target(
            name: "SculptorTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.mishandled.sculptor.tests",
            deploymentTargets: .iOS("17.0"),
            sources: ["Sculptor/Tests/**"],
            dependencies: [.target(name: "Sculptor")]
        )
    ]
)
```

- [ ] **Step 4: Generate and list schemes**

```bash
tuist generate --no-open
xcodebuild -workspace Sculptor.xcworkspace -list
```
Expected: schemes include `AudioEngine` (package), `DesignSystem`, `Sculptor`, `Sculptor-Workspace`. If the package scheme is missing from `-list`, it still resolves by name in the next step (Xcode auto-creates package schemes on demand).

- [ ] **Step 5: Run tests — package scheme + workspace scheme**

```bash
xcodebuild test -workspace Sculptor.xcworkspace -scheme AudioEngine \
  -destination "platform=iOS Simulator,name={SIM}" > /tmp/task2-pkg.log 2>&1
tail -30 /tmp/task2-pkg.log
xcodebuild test -workspace Sculptor.xcworkspace -scheme Sculptor-Workspace \
  -destination "platform=iOS Simulator,name={SIM}" > /tmp/task2-ws.log 2>&1
tail -30 /tmp/task2-ws.log
```
Expected: both `** TEST SUCCEEDED **`. AudioEngine test count matches its pre-move count (the workspace scheme may or may not still include package tests — the package-scheme run is the authoritative one for AudioEngine; record which so later tasks know).

- [ ] **Step 6: Commit**

```bash
git add -A
git -c user.name='Sculptor' -c user.email='dev@sculptor.local' commit \
  -m "refactor: AudioEngine becomes local SPM package under Packages/"
```

---

### Task 3: DesignSystem → local SPM package (with font resources)

**Files:**
- Create: `Packages/DesignSystem/Package.swift`
- Move: `DesignSystem/Sources/{Components,Fonts,Tokens}` → `Packages/DesignSystem/Sources/DesignSystem/` (keep subdirectory names)
- Move: `DesignSystem/Resources/Fonts/*.ttf` → `Packages/DesignSystem/Sources/DesignSystem/Resources/Fonts/` (5 files)
- Move: `DesignSystem/Tests/*.swift` → `Packages/DesignSystem/Tests/DesignSystemTests/` (6 files after Task 1)
- Modify: `Project.swift` (drop DesignSystem targets, add package)

**Interfaces:**
- Consumes: Task 2's `packages:` block in Project.swift.
- Produces: `import DesignSystem` unchanged for app sources; `Bundle.module` now SPM-native (FontRegistrar needs zero code change); package scheme `DesignSystem`.

- [ ] **Step 1: Move everything**

```bash
mkdir -p Packages/DesignSystem/Sources/DesignSystem Packages/DesignSystem/Tests/DesignSystemTests
git mv DesignSystem/Sources/Components Packages/DesignSystem/Sources/DesignSystem/Components
git mv DesignSystem/Sources/Fonts Packages/DesignSystem/Sources/DesignSystem/Fonts
git mv DesignSystem/Sources/Tokens Packages/DesignSystem/Sources/DesignSystem/Tokens
git mv DesignSystem/Sources/DesignSystem.swift Packages/DesignSystem/Sources/DesignSystem/
git mv DesignSystem/Resources Packages/DesignSystem/Sources/DesignSystem/Resources
git mv DesignSystem/Tests/*.swift Packages/DesignSystem/Tests/DesignSystemTests/
rmdir DesignSystem/Sources DesignSystem/Tests DesignSystem 2>/dev/null; true
```

- [ ] **Step 2: Write the manifest**

Create `Packages/DesignSystem/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DesignSystem",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"])
    ],
    targets: [
        .target(
            name: "DesignSystem",
            resources: [.process("Resources")]
        ),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"])
    ],
    swiftLanguageModes: [.v5]
)
```

- [ ] **Step 3: Update Project.swift**

In `Project.swift`: add `.package(path: "Packages/DesignSystem")` to `packages:`, delete the `DesignSystem` and `DesignSystemTests` target blocks entirely, and in the Sculptor target change `.target(name: "DesignSystem")` → `.package(product: "DesignSystem")`. Result:

```swift
import ProjectDescription

let project = Project(
    name: "Sculptor",
    packages: [
        .package(path: "Packages/AudioEngine"),
        .package(path: "Packages/DesignSystem")
    ],
    targets: [
        .target(
            name: "Sculptor",
            destinations: .iOS,
            product: .app,
            bundleId: "com.mishandled.sculptor",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .extendingDefault(with: [
                "UILaunchScreen": [:],
                "UIBackgroundModes": ["audio"]
            ]),
            sources: ["Sculptor/Sources/**"],
            dependencies: [
                .package(product: "AudioEngine"),
                .package(product: "DesignSystem")
            ]
        ),
        .target(
            name: "SculptorTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.mishandled.sculptor.tests",
            deploymentTargets: .iOS("17.0"),
            sources: ["Sculptor/Tests/**"],
            dependencies: [.target(name: "Sculptor")]
        )
    ]
)
```

- [ ] **Step 4: Generate and test all three suites**

```bash
tuist generate --no-open
for SCHEME in AudioEngine DesignSystem Sculptor-Workspace; do
  xcodebuild test -workspace Sculptor.xcworkspace -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,name={SIM}" > "/tmp/task3-$SCHEME.log" 2>&1
  tail -5 "/tmp/task3-$SCHEME.log"
done
```
Expected: three `** TEST SUCCEEDED **`. FontTests inside the DesignSystem package are the font-resource proof: they assert `Dock-Lexend-*` PostScript resolvability via `Bundle.module` fonts. If FontTests fail with missing resource, switch `.process("Resources")` → `.copy("Resources")` in the manifest and rerun (known SPM edge case; both keep `Bundle.module.url(forResource:withExtension:)` working).

- [ ] **Step 5: Launch app in simulator (font + audio smoke)**

Build and run the `Sculptor` scheme on {SIM} (XcodeBuildMCP `build_run_sim` or `xcodebuild ... build` + `simctl install/launch`). Take a screenshot. Expected: home screen renders in Lexend (geometric sans, NOT iOS system SF), teal accent present. If system font shows, fonts didn't land in `Bundle.module` — see Step 4 fallback. (Gotcha: sim font cache can lie for *tests*; a fresh screenshot of real UI is ground truth.)

- [ ] **Step 6: Commit**

```bash
git add -A
git -c user.name='Sculptor' -c user.email='dev@sculptor.local' commit \
  -m "refactor: DesignSystem becomes local SPM package with bundled Lexend resources"
```

---

### Task 4: AudioEngine free functions → caseless enums

**Files:**
- Modify: `Packages/AudioEngine/Sources/AudioEngine/Downsample.swift`
- Modify: `Packages/AudioEngine/Sources/AudioEngine/Fade.swift`
- Modify: `Packages/AudioEngine/Sources/AudioEngine/AudioSessionPolicy.swift`
- Modify: `Packages/AudioEngine/Sources/AudioEngine/NoiseEngine.swift` (call sites at former lines 104, 126, 249, 277, 297)
- Test: `Packages/AudioEngine/Tests/AudioEngineTests/{DownsampleTests,FadeTests,AudioSessionPolicyTests}.swift`

**Interfaces:**
- Consumes: package layout from Task 2.
- Produces: `Downsample.resample(_:to:) -> [Float]` (public), `Fade.curve(from:steps:) -> [Float]` (internal), `AudioSessionPolicy.interruptionAction(type:options:wasPlaying:) -> InterruptionAction` (public), `AudioSessionPolicy.routeChangeAction(reason:) -> RouteAction` (public). `InterruptionAction`/`RouteAction` enums stay top-level and unchanged.

- [ ] **Step 1: Update tests to the new API (they must fail to compile first)**

In `DownsampleTests.swift` replace every `downsample(` with `Downsample.resample(`:
```swift
#expect(Downsample.resample([], to: 128) == [])
#expect(Downsample.resample([1, 2, 3, 4], to: 2) == [1.5, 3.5])
#expect(Downsample.resample([1, 2, 3], to: 5) == [1, 2, 3])
#expect(Downsample.resample([1, 2, 3, 4], to: 0) == [2.5])
```

In `FadeTests.swift` replace every `fadeCurve(` with `Fade.curve(`:
```swift
#expect(Fade.curve(from: 1, steps: 4) == [0.75, 0.5, 0.25, 0])
#expect(Fade.curve(from: 1, steps: 0).isEmpty)
#expect(Fade.curve(from: 1, steps: -3).isEmpty)
#expect(Fade.curve(from: 0.6, steps: 7).last == 0)
```

In `AudioSessionPolicyTests.swift` prefix the calls with `AudioSessionPolicy.`:
```swift
#expect(AudioSessionPolicy.interruptionAction(type: .began, options: [], wasPlaying: true) == .pause)
#expect(AudioSessionPolicy.interruptionAction(type: .ended, options: .shouldResume, wasPlaying: true) == .resume)
#expect(AudioSessionPolicy.interruptionAction(type: .ended, options: .shouldResume, wasPlaying: false) == .none)
#expect(AudioSessionPolicy.interruptionAction(type: .ended, options: [], wasPlaying: true) == .none)
#expect(AudioSessionPolicy.routeChangeAction(reason: .oldDeviceUnavailable) == .pause)
#expect(AudioSessionPolicy.routeChangeAction(reason: .newDeviceAvailable) == .none)
#expect(AudioSessionPolicy.routeChangeAction(reason: .categoryChange) == .none)
```

- [ ] **Step 2: Verify compile failure**

```bash
xcodebuild test -workspace Sculptor.xcworkspace -scheme AudioEngine \
  -destination "platform=iOS Simulator,name={SIM}" > /tmp/task4-red.log 2>&1
tail -20 /tmp/task4-red.log
```
Expected: BUILD FAILED — `cannot find 'Downsample' in scope` (and friends).

- [ ] **Step 3: Wrap the implementations (bodies verbatim)**

`Downsample.swift`:
```swift
/// Block-averages samples into contiguous blocks (the mean of each block).
public enum Downsample {
    /// `count` is clamped to >= 1. Empty input returns []. Input shorter
    /// than `count` is returned unchanged.
    public static func resample(_ samples: [Float], to count: Int) -> [Float] {
        let n = samples.count
        guard n > 0 else { return [] }
        let k = max(1, count)
        guard n > k else { return samples }
        var out = [Float](repeating: 0, count: k)
        for i in 0..<k {
            let lo = i * n / k
            let hi = (i + 1) * n / k
            // Guard against a zero-width block (hi == lo) from integer rounding.
            let end = max(hi, lo + 1)
            var sum: Float = 0
            var c = 0
            for j in lo..<min(end, n) { sum += samples[j]; c += 1 }
            out[i] = c > 0 ? sum / Float(c) : 0
        }
        return out
    }
}
```

`Fade.swift`:
```swift
enum Fade {
    /// Linear fade curve from `start` down to 0 in `steps` equal decrements.
    /// The final element is always exactly 0. Empty for steps <= 0.
    static func curve(from start: Float, steps: Int) -> [Float] {
        guard steps > 0 else { return [] }
        return (1...steps).map { start * Float(steps - $0) / Float(steps) }
    }
}
```

`AudioSessionPolicy.swift`:
```swift
import AVFoundation

public enum InterruptionAction: Equatable { case pause, resume, none }
public enum RouteAction: Equatable { case pause, none }

/// Pure decisions for AVAudioSession notifications.
public enum AudioSessionPolicy {
    /// Decision for an interruption notification.
    public static func interruptionAction(
        type: AVAudioSession.InterruptionType,
        options: AVAudioSession.InterruptionOptions,
        wasPlaying: Bool
    ) -> InterruptionAction {
        switch type {
        case .began:
            return .pause
        case .ended:
            return (options.contains(.shouldResume) && wasPlaying) ? .resume : .none
        @unknown default:
            return .none
        }
    }

    /// Decision for a route-change notification.
    public static func routeChangeAction(reason: AVAudioSession.RouteChangeReason) -> RouteAction {
        reason == .oldDeviceUnavailable ? .pause : .none
    }
}
```

- [ ] **Step 4: Update NoiseEngine.swift call sites (5)**

| Former line | Old | New |
|---|---|---|
| 104 | `downsample(samples, to: Self.scopePointCount)` | `Downsample.resample(samples, to: Self.scopePointCount)` |
| 126 | `interruptionAction(type: .ended, options: options, wasPlaying: wasPlayingBeforeInterruption) == .resume` | `AudioSessionPolicy.interruptionAction(type: .ended, options: options, wasPlaying: wasPlayingBeforeInterruption) == .resume` |
| 249 | `fadeCurve(from: engine.mainMixerNode.outputVolume, steps: steps)` | `Fade.curve(from: engine.mainMixerNode.outputVolume, steps: steps)` |
| 277 | `switch interruptionAction(type: type, options: options, wasPlaying: wasPlayingBeforeInterruption)` | `switch AudioSessionPolicy.interruptionAction(type: type, options: options, wasPlaying: wasPlayingBeforeInterruption)` |
| 297 | `if routeChangeAction(reason: reason) == .pause { stop() }` | `if AudioSessionPolicy.routeChangeAction(reason: reason) == .pause { stop() }` |

- [ ] **Step 5: Run AudioEngine + workspace suites**

```bash
xcodebuild test -workspace Sculptor.xcworkspace -scheme AudioEngine \
  -destination "platform=iOS Simulator,name={SIM}" > /tmp/task4-green.log 2>&1
tail -10 /tmp/task4-green.log
xcodebuild test -workspace Sculptor.xcworkspace -scheme Sculptor-Workspace \
  -destination "platform=iOS Simulator,name={SIM}" > /tmp/task4-ws.log 2>&1
tail -10 /tmp/task4-ws.log
```
Expected: both `** TEST SUCCEEDED **`, counts unchanged from Task 3.

- [ ] **Step 6: Commit**

```bash
git add -A
git -c user.name='Sculptor' -c user.email='dev@sculptor.local' commit \
  -m "refactor: AudioEngine free functions become static methods on caseless enums"
```

---

### Task 5: DesignSystem free functions → caseless enums

**Files:**
- Modify: `Packages/DesignSystem/Sources/DesignSystem/Components/MiniEQIcon.swift`
- Modify: `Packages/DesignSystem/Sources/DesignSystem/Components/ScopeVisualizer.swift`
- Modify: `Packages/DesignSystem/Sources/DesignSystem/Components/BandSlider.swift`
- Modify: `Packages/DesignSystem/Sources/DesignSystem/Tokens/DockColor.swift`
- Modify: `Packages/DesignSystem/Sources/DesignSystem/Components/PlayHeroButton.swift` (former line 57, `dockRGB` call)
- Test: `Packages/DesignSystem/Tests/DesignSystemTests/{MiniEQIconTests,ScopeVisualizerTests,BandSliderTests,DockColorTests}.swift`

**Interfaces:**
- Consumes: package layout from Task 3.
- Produces: `MiniEQGeometry.barHeight(gain:range:maxHeight:) -> CGFloat` (public), `ScopeGeometry.y(value:height:) -> CGFloat` (public), `SliderGeometry.fillFraction(value:in:) -> CGFloat` (public), `DockColorHex.rgb(hex:) -> (Double, Double, Double)` (internal).

- [ ] **Step 1: Update tests to the new API**

`MiniEQIconTests.swift`: every `miniEQBarHeight(` → `MiniEQGeometry.barHeight(`.
`ScopeVisualizerTests.swift`: every `scopeY(` → `ScopeGeometry.y(`.
`BandSliderTests.swift`: every `bandSliderFillFraction(` → `SliderGeometry.fillFraction(`.
`DockColorTests.swift`: every `dockRGB(` → `DockColorHex.rgb(`.
Arguments/expectations stay byte-identical, e.g.:
```swift
#expect(MiniEQGeometry.barHeight(gain: 12, range: r, maxHeight: 20) == 20)
#expect(ScopeGeometry.y(value: 0, height: 100) == 50)
#expect(abs(SliderGeometry.fillFraction(value: -6, in: -24...12) - 0.5) < 0.001)
let (r, g, b) = DockColorHex.rgb(hex: 0x2ED3B7)
```

- [ ] **Step 2: Verify compile failure**

```bash
xcodebuild test -workspace Sculptor.xcworkspace -scheme DesignSystem \
  -destination "platform=iOS Simulator,name={SIM}" > /tmp/task5-red.log 2>&1
tail -20 /tmp/task5-red.log
```
Expected: BUILD FAILED — `cannot find 'MiniEQGeometry' in scope` (and friends).

- [ ] **Step 3: Wrap implementations (bodies verbatim)**

In `MiniEQIcon.swift`, replace the free function with:
```swift
public enum MiniEQGeometry {
    /// Height of one mini-EQ bar for `gain` within `range`, clamped to 0...maxHeight.
    public static func barHeight(gain: Float, range: ClosedRange<Float>, maxHeight: CGFloat) -> CGFloat {
        let clamped = min(range.upperBound, max(range.lowerBound, gain))
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return maxHeight * CGFloat((clamped - range.lowerBound) / span)
    }
}
```

In `ScopeVisualizer.swift`:
```swift
public enum ScopeGeometry {
    /// Maps a sample (roughly -1...1, clamped) to a Y coordinate: 0 -> vertical
    /// center, +1 -> top (0), -1 -> bottom (height).
    public static func y(value: Float, height: CGFloat) -> CGFloat {
        let clamped = CGFloat(min(1, max(-1, value)))
        return height / 2 - clamped * (height / 2)
    }
}
```

In `BandSlider.swift`:
```swift
public enum SliderGeometry {
    /// Fraction (0...1) of the track that should be filled for `value` within `range`.
    public static func fillFraction(value: Float, in range: ClosedRange<Float>) -> CGFloat {
        let clamped = min(range.upperBound, max(range.lowerBound, value))
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat((clamped - range.lowerBound) / span)
    }
}
```

In `DockColor.swift`, replace the free `dockRGB` with:
```swift
/// Decodes 0xRRGGBB integers into sRGB components in 0...1.
enum DockColorHex {
    static func rgb(hex: UInt32) -> (Double, Double, Double) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        return (r, g, b)
    }
}
```

- [ ] **Step 4: Update in-module call sites (4)**

| File (former line) | Old | New |
|---|---|---|
| `MiniEQIcon.swift` (31) | `miniEQBarHeight(gain: gains[i], range: range, maxHeight: maxH)` | `MiniEQGeometry.barHeight(gain: gains[i], range: range, maxHeight: maxH)` |
| `ScopeVisualizer.swift` (30) | `scopeY(value: samples[i], height: size.height)` | `ScopeGeometry.y(value: samples[i], height: size.height)` |
| `BandSlider.swift` (25) | `bandSliderFillFraction(value: value, in: range)` | `SliderGeometry.fillFraction(value: value, in: range)` |
| `DockColor.swift` (13) | `let (r, g, b) = dockRGB(hex: hex)` | `let (r, g, b) = DockColorHex.rgb(hex: hex)` |
| `PlayHeroButton.swift` (57) | `let (r, g, b) = dockRGB(hex: 0x0e7d6c)` | `let (r, g, b) = DockColorHex.rgb(hex: 0x0e7d6c)` |

- [ ] **Step 5: Run DesignSystem + workspace suites**

```bash
xcodebuild test -workspace Sculptor.xcworkspace -scheme DesignSystem \
  -destination "platform=iOS Simulator,name={SIM}" > /tmp/task5-green.log 2>&1
tail -10 /tmp/task5-green.log
xcodebuild test -workspace Sculptor.xcworkspace -scheme Sculptor-Workspace \
  -destination "platform=iOS Simulator,name={SIM}" > /tmp/task5-ws.log 2>&1
tail -10 /tmp/task5-ws.log
```
Expected: both `** TEST SUCCEEDED **`, counts unchanged.

- [ ] **Step 6: Commit**

```bash
git add -A
git -c user.name='Sculptor' -c user.email='dev@sculptor.local' commit \
  -m "refactor: DesignSystem geometry helpers become static methods on caseless enums"
```

---

### Task 6: Sculptor app free functions → caseless enums + final verification

**Files:**
- Modify: `Sculptor/Sources/PresetMetrics.swift`
- Modify: `Sculptor/Sources/SelectionPersistence.swift`
- Modify: `Sculptor/Sources/SleepFormatting.swift`
- Modify: `Sculptor/Sources/PresetsView.swift` (former lines 52, 131, 137)
- Modify: `Sculptor/Sources/PlaybackViewModel.swift` (former lines 208, 227)
- Modify: `Sculptor/Sources/HomeView.swift` (former line 145)
- Test: `Sculptor/Tests/{PresetMetricsTests,SelectionPersistenceTests,SleepFormattingTests}.swift`

**Interfaces:**
- Consumes: `PresetSelection` and `NoisePreset` from AudioEngine (import unchanged).
- Produces: `PresetMetrics.bandsRaisedCount(_:) -> Int`, `PresetMetrics.copyName(of:) -> String`, `PresetMetrics.sanitizedRename(old:new:) -> String`, `SelectionPersistence.token(_:) -> String?`, `SelectionPersistence.parse(_:) -> PresetSelection?`, `SleepFormatting.countdown(_:) -> String` (all internal).

- [ ] **Step 1: Update tests to the new API**

`PresetMetricsTests.swift`: `bandsRaisedCount(` → `PresetMetrics.bandsRaisedCount(`, `copyName(` → `PresetMetrics.copyName(`, `sanitizedRename(` → `PresetMetrics.sanitizedRename(`.
`SelectionPersistenceTests.swift`: `selectionToken(` → `SelectionPersistence.token(`, `parseSelectionToken(` → `SelectionPersistence.parse(`.
`SleepFormattingTests.swift`: `formatCountdown(` → `SleepFormatting.countdown(`.
Arguments/expectations byte-identical.

- [ ] **Step 2: Verify compile failure**

```bash
xcodebuild test -workspace Sculptor.xcworkspace -scheme Sculptor \
  -destination "platform=iOS Simulator,name={SIM}" > /tmp/task6-red.log 2>&1
tail -20 /tmp/task6-red.log
```
Expected: BUILD FAILED — `cannot find 'PresetMetrics' in scope` (and friends).

- [ ] **Step 3: Wrap implementations (bodies verbatim)**

`PresetMetrics.swift`:
```swift
import Foundation

enum PresetMetrics {
    /// Number of bands raised above flat (gain strictly greater than 0).
    static func bandsRaisedCount(_ gains: [Float]) -> Int {
        gains.filter { $0 > 0 }.count
    }

    /// Name for a duplicated preset.
    static func copyName(of name: String) -> String {
        "Copy of \(name)"
    }

    /// Resolves a rename submission: trimmed; an empty result reverts to the old name.
    static func sanitizedRename(old: String, new: String) -> String {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? old : trimmed
    }
}
```

`SelectionPersistence.swift`:
```swift
import AudioEngine
import Foundation

enum SelectionPersistence {
    /// Stable string token for persisting the active selection. nil for `.none`.
    static func token(_ selection: PresetSelection) -> String? {
        switch selection {
        case .none:           return nil
        case .builtin(let p): return "builtin:\(builtinKey(p))"
        case .custom(let id): return "custom:\(id.uuidString)"
        }
    }

    /// Parses a token back to a selection. nil if malformed/unknown.
    static func parse(_ token: String) -> PresetSelection? {
        if token.hasPrefix("builtin:") {
            let key = String(token.dropFirst("builtin:".count))
            return builtinFromKey(key).map { PresetSelection.builtin($0) }
        }
        if token.hasPrefix("custom:") {
            let raw = String(token.dropFirst("custom:".count))
            if let id = UUID(uuidString: raw) { return .custom(id) }
        }
        return nil
    }

    private static func builtinKey(_ p: NoisePreset) -> String {
        switch p {
        case .white:         return "white"
        case .pink:          return "pink"
        case .brown:         return "brown"
        case .grey:          return "grey"
        case .speechBlocker: return "speechBlocker"
        }
    }

    private static func builtinFromKey(_ key: String) -> NoisePreset? {
        switch key {
        case "white":         return .white
        case "pink":          return .pink
        case "brown":         return .brown
        case "grey":          return .grey
        case "speechBlocker": return .speechBlocker
        default:              return nil
        }
    }
}
```

`SleepFormatting.swift`:
```swift
import Foundation

enum SleepFormatting {
    /// Zero-padded MM:SS for a countdown. Negative input clamps to "00:00".
    static func countdown(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
```

- [ ] **Step 4: Update app call sites (6)**

| File (former line) | Old | New |
|---|---|---|
| `PresetsView.swift` (52) | `\(bandsRaisedCount(preset.gains)) bands raised` | `\(PresetMetrics.bandsRaisedCount(preset.gains)) bands raised` |
| `PresetsView.swift` (131) | `preset.name = sanitizedRename(old: preset.name, new: renameText)` | `preset.name = PresetMetrics.sanitizedRename(old: preset.name, new: renameText)` |
| `PresetsView.swift` (137) | `CustomPreset(name: copyName(of: preset.name), ...)` | `CustomPreset(name: PresetMetrics.copyName(of: preset.name), ...)` |
| `PlaybackViewModel.swift` (208) | `let sel = parseSelectionToken(token),` | `let sel = SelectionPersistence.parse(token),` |
| `PlaybackViewModel.swift` (227) | `if let token = selectionToken(selection) {` | `if let token = SelectionPersistence.token(selection) {` |
| `HomeView.swift` (145) | `Text(formatCountdown(Int(remaining)))` | `Text(SleepFormatting.countdown(Int(remaining)))` |

- [ ] **Step 5: Full verification — all suites + zero free functions + app launch**

```bash
for SCHEME in AudioEngine DesignSystem Sculptor-Workspace; do
  xcodebuild test -workspace Sculptor.xcworkspace -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,name={SIM}" > "/tmp/task6-$SCHEME.log" 2>&1
  tail -5 "/tmp/task6-$SCHEME.log"
done
grep -rn "^public func\|^func\|^private func" \
  Packages/AudioEngine/Sources Packages/DesignSystem/Sources Sculptor/Sources --include="*.swift"
```
Expected: three `** TEST SUCCEEDED **`; the grep prints NOTHING (zero top-level functions remain). Then launch the app on {SIM}, screenshot: Lexend fonts render, play a preset briefly to confirm audio path (scope visualizer animates).

- [ ] **Step 6: Commit**

```bash
git add -A
git -c user.name='Sculptor' -c user.email='dev@sculptor.local' commit \
  -m "refactor: app-level free functions become static methods on caseless enums"
```

---

## Deviation from spec

Spec sketched 3 commits; plan splits the same work into 6 (one per task) for bisectability and per-task review. Content identical.
