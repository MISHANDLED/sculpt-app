# Phase 0 Audio Spike Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove that synthesized white noise through an 8-band EQ sounds clean on headphones and that white/pink/brown emerge by tilting bands.

**Architecture:** Tuist-generated workspace with two targets — `AudioEngine` (framework, the defensible audio core, no UI) and `Sculptor` (SwiftUI app consuming it). White noise is produced by an `AVAudioSourceNode` render callback, shaped by an `AVAudioUnitEQ` (8 parametric bands), mixed to output. The UI drives only the EQ band gains; it never touches the render thread.

**Tech Stack:** Swift 6.3, Xcode 26.5, Tuist 4.200.5, AVFoundation (AVAudioEngine / AVAudioSourceNode / AVAudioUnitEQ), SwiftUI, Swift Testing.

## Global Constraints

- iOS deployment target floor: `iOS 17.0`.
- Project generation via **Tuist 4.200.5** only (`Project.swift` manifest). No hand-edited `.xcodeproj`.
- Band frequencies (Hz), fixed order: `60, 125, 250, 500, 1000, 2000, 4000, 8000`.
- Slider/gain range: `-24 ... +12` dB.
- Render callback is real-time: no locks, no heap allocation, no Swift ARC traffic inside it — scalars only.
- This is a throwaway spike: NO presets persistence, iCloud, animation, stereo-width UI, background mode, or Dock design system.
- Bundle id prefix: `com.sculptor`.
- Test framework: Swift Testing (`import Testing`, `@Test`).

---

### Task 1: Tuist skeleton that builds an empty app + framework

**Files:**
- Create: `Project.swift`
- Create: `Tuist.swift`
- Create: `AudioEngine/Sources/AudioEngine.swift`
- Create: `AudioEngine/Tests/PlaceholderTests.swift`
- Create: `Sculptor/Sources/SculptorApp.swift`
- Create: `Sculptor/Sources/RootView.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: a buildable `Sculptor.xcworkspace` with schemes `AudioEngine` and `Sculptor`.

- [ ] **Step 1: Write `Tuist.swift`** (repo-root config — pins nothing, just marks the Tuist project root)

```swift
import ProjectDescription

let tuist = Tuist()
```

- [ ] **Step 2: Write `Project.swift`**

```swift
import ProjectDescription

let project = Project(
    name: "Sculptor",
    targets: [
        .target(
            name: "AudioEngine",
            destinations: .iOS,
            product: .framework,
            bundleId: "com.sculptor.audioengine",
            deploymentTargets: .iOS("17.0"),
            sources: ["AudioEngine/Sources/**"],
            dependencies: []
        ),
        .target(
            name: "AudioEngineTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.sculptor.audioengine.tests",
            deploymentTargets: .iOS("17.0"),
            sources: ["AudioEngine/Tests/**"],
            dependencies: [.target(name: "AudioEngine")]
        ),
        .target(
            name: "Sculptor",
            destinations: .iOS,
            product: .app,
            bundleId: "com.sculptor.app",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .extendingDefault(with: [
                "UILaunchScreen": [:]
            ]),
            sources: ["Sculptor/Sources/**"],
            dependencies: [.target(name: "AudioEngine")]
        )
    ]
)
```

- [ ] **Step 3: Write placeholder source files** (globs need at least one file each)

`AudioEngine/Sources/AudioEngine.swift`:
```swift
// AudioEngine module — Phase 0 audio spike core.
public enum AudioEngineModule {
    public static let bandFrequencies: [Float] = [60, 125, 250, 500, 1000, 2000, 4000, 8000]
}
```

`AudioEngine/Tests/PlaceholderTests.swift`:
```swift
import Testing
@testable import AudioEngine

@Test func bandFrequenciesAreEight() {
    #expect(AudioEngineModule.bandFrequencies.count == 8)
}
```

`Sculptor/Sources/SculptorApp.swift`:
```swift
import SwiftUI

@main
struct SculptorApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
```

`Sculptor/Sources/RootView.swift`:
```swift
import SwiftUI

struct RootView: View {
    var body: some View {
        Text("Sculptor spike")
    }
}
```

- [ ] **Step 4: Generate the project**

Run: `cd "/Users/devansh.mohata@zomato.com/Documents/Random/Noise" && tuist generate --no-open`
Expected: succeeds, creates `Sculptor.xcworkspace` and `Sculptor.xcodeproj`.
If Tuist errors on Xcode 26.5 compatibility, STOP and report — fall back to a hand-written minimal project per the spec.

- [ ] **Step 5: Confirm schemes exist**

Run: `xcodebuild -workspace Sculptor.xcworkspace -list`
Expected: schemes include `AudioEngine` and `Sculptor`.

- [ ] **Step 6: Build the app for the simulator**

Run: `xcodebuild -workspace Sculptor.xcworkspace -scheme Sculptor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Run the placeholder test**

Run: `xcodebuild -workspace Sculptor.xcworkspace -scheme AudioEngine -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 8: Commit**

```bash
git init
printf '%s\n' '.build/' 'Derived/' '*.xcworkspace' '*.xcodeproj' '.DS_Store' > .gitignore
git add .gitignore Tuist.swift Project.swift AudioEngine Sculptor docs
git commit -m "chore: tuist skeleton with AudioEngine framework + Sculptor app"
```

---

### Task 2: White-noise source (pure, testable PRNG)

**Files:**
- Create: `AudioEngine/Sources/NoiseSource.swift`
- Test: `AudioEngine/Tests/NoiseSourceTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `struct NoiseSource` with `init(seed: UInt64)` and `mutating func next() -> Float` returning a sample in `[-1, 1]`.

- [ ] **Step 1: Write the failing tests**

`AudioEngine/Tests/NoiseSourceTests.swift`:
```swift
import Testing
@testable import AudioEngine

@Test func samplesStayInRange() {
    var s = NoiseSource(seed: 12345)
    for _ in 0..<10_000 {
        let v = s.next()
        #expect(v >= -1 && v <= 1)
    }
}

@Test func samplesAreNotConstant() {
    var s = NoiseSource(seed: 1)
    let first = s.next()
    var sawDifferent = false
    for _ in 0..<100 where s.next() != first { sawDifferent = true }
    #expect(sawDifferent)
}

@Test func differentSeedsDecorrelate() {
    var a = NoiseSource(seed: 0xAAAA)
    var b = NoiseSource(seed: 0x5555)
    var identical = 0
    for _ in 0..<1000 where a.next() == b.next() { identical += 1 }
    #expect(identical < 10)
}

@Test func zeroSeedDoesNotStall() {
    var s = NoiseSource(seed: 0)
    #expect(s.next() != s.next())
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -workspace Sculptor.xcworkspace -scheme AudioEngine -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`
Expected: FAIL — `NoiseSource` undefined.

- [ ] **Step 3: Write the implementation**

`AudioEngine/Sources/NoiseSource.swift`:
```swift
/// Real-time-safe white-noise source. Value semantics, no allocation.
/// `next()` averages 3 xorshift draws (central-limit smoothing) so the
/// noise sounds less "digital" than a single uniform sample.
public struct NoiseSource {
    private var state: UInt64

    public init(seed: UInt64) {
        // xorshift64 stalls on 0 — substitute a fixed nonzero seed.
        state = seed != 0 ? seed : 0x9E37_79B9_7F4A_7C15
    }

    public mutating func next() -> Float {
        var sum: Float = 0
        for _ in 0..<3 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            // top 24 bits → [0,1), then map to [-1,1]
            let u = Float(state >> 40) * (1.0 / Float(1 << 24))
            sum += u * 2 - 1
        }
        return sum / 3
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -workspace Sculptor.xcworkspace -scheme AudioEngine -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add AudioEngine/Sources/NoiseSource.swift AudioEngine/Tests/NoiseSourceTests.swift
git commit -m "feat: real-time-safe white-noise source"
```

---

### Task 3: Noise presets (white / pink / brown band-gain arrays)

**Files:**
- Create: `AudioEngine/Sources/NoisePreset.swift`
- Test: `AudioEngine/Tests/NoisePresetTests.swift`

**Interfaces:**
- Consumes: `AudioEngineModule.bandFrequencies` (from Task 1).
- Produces: `enum NoisePreset { case white, pink, brown }` with `var gains: [Float]` returning 8 dB values clamped to `-24...12`.

- [ ] **Step 1: Write the failing tests**

`AudioEngine/Tests/NoisePresetTests.swift`:
```swift
import Testing
@testable import AudioEngine

@Test func whiteIsFlat() {
    #expect(NoisePreset.white.gains == [Float](repeating: 0, count: 8))
}

@Test func eachPresetHasEightBands() {
    for p in [NoisePreset.white, .pink, .brown] {
        #expect(p.gains.count == 8)
    }
}

@Test func pinkAndBrownTiltDownWithFrequency() {
    // Low frequencies louder than high → non-increasing across bands.
    for p in [NoisePreset.pink, .brown] {
        let g = p.gains
        for i in 1..<g.count {
            #expect(g[i] <= g[i - 1])
        }
    }
}

@Test func brownTiltsSteeperThanPink() {
    // At the top band, brown is attenuated at least as much as pink.
    #expect(NoisePreset.brown.gains.last! <= NoisePreset.pink.gains.last!)
}

@Test func gainsAreClamped() {
    for p in [NoisePreset.white, .pink, .brown] {
        for g in p.gains { #expect(g >= -24 && g <= 12) }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -workspace Sculptor.xcworkspace -scheme AudioEngine -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`
Expected: FAIL — `NoisePreset` undefined.

- [ ] **Step 3: Write the implementation**

`AudioEngine/Sources/NoisePreset.swift`:
```swift
import Foundation

/// Built-in noise colors expressed as 8-band EQ tilts over white noise.
/// Referenced to the lowest band (60 Hz = 0 dB); higher bands attenuate.
/// EQ-tilt approximates true pink/brown but is the product's real mechanism.
public enum NoisePreset: CaseIterable {
    case white, pink, brown

    /// dB per octave of attenuation, relative to the lowest band.
    private var slopePerOctave: Float {
        switch self {
        case .white: return 0
        case .pink:  return 3
        case .brown: return 6
        }
    }

    public var gains: [Float] {
        let freqs = AudioEngineModule.bandFrequencies
        guard let base = freqs.first else { return [] }
        return freqs.map { f in
            let octaves = log2(f / base)            // 0 at base, grows upward
            let g = -slopePerOctave * octaves
            return min(12, max(-24, g))
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -workspace Sculptor.xcworkspace -scheme AudioEngine -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add AudioEngine/Sources/NoisePreset.swift AudioEngine/Tests/NoisePresetTests.swift
git commit -m "feat: white/pink/brown noise presets as EQ tilts"
```

---

### Task 4: NoiseEngine (AVAudioEngine graph + EQ + session)

**Files:**
- Create: `AudioEngine/Sources/NoiseEngine.swift`
- Test: `AudioEngine/Tests/NoiseEngineTests.swift`

**Interfaces:**
- Consumes: `NoiseSource` (Task 2), `NoisePreset` (Task 3), `AudioEngineModule.bandFrequencies` (Task 1).
- Produces: `final class NoiseEngine` with:
  - `init()`
  - `var bandCount: Int` (== 8)
  - `func centerFrequency(band: Int) -> Float`
  - `func setGain(band: Int, dB: Float)` (clamps to -24...12)
  - `func gain(band: Int) -> Float`
  - `func apply(_ preset: NoisePreset)`
  - `func start() throws`
  - `func stop()`

- [ ] **Step 1: Write the failing tests** (only the audio-thread-independent surface is unit-tested; sound itself is validated manually)

`AudioEngine/Tests/NoiseEngineTests.swift`:
```swift
import Testing
@testable import AudioEngine

@Test func hasEightBandsAtExpectedFrequencies() {
    let e = NoiseEngine()
    #expect(e.bandCount == 8)
    let expected: [Float] = [60, 125, 250, 500, 1000, 2000, 4000, 8000]
    for i in 0..<e.bandCount {
        #expect(e.centerFrequency(band: i) == expected[i])
    }
}

@Test func setGainClampsToRange() {
    let e = NoiseEngine()
    e.setGain(band: 0, dB: 999)
    #expect(e.gain(band: 0) == 12)
    e.setGain(band: 0, dB: -999)
    #expect(e.gain(band: 0) == -24)
    e.setGain(band: 0, dB: 5)
    #expect(e.gain(band: 0) == 5)
}

@Test func applyPresetSetsAllBands() {
    let e = NoiseEngine()
    e.apply(.white)
    for i in 0..<e.bandCount { #expect(e.gain(band: i) == 0) }
    e.apply(.brown)
    #expect(e.gain(band: 7) < e.gain(band: 0))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -workspace Sculptor.xcworkspace -scheme AudioEngine -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`
Expected: FAIL — `NoiseEngine` undefined.

- [ ] **Step 3: Write the implementation**

`AudioEngine/Sources/NoiseEngine.swift`:
```swift
import AVFoundation

/// Owns the AVAudioEngine graph: white-noise source → 8-band EQ → output.
/// UI mutates only EQ band gains (audio-unit thread-safe); it never touches
/// the render callback.
public final class NoiseEngine {
    private let engine = AVAudioEngine()
    private let eq: AVAudioUnitEQ
    private var sourceNode: AVAudioSourceNode!

    // Per-channel PRNG state, allocated once. Pointers are captured by the
    // render block so it never retains `self` or allocates on the audio thread.
    private let stateL = UnsafeMutablePointer<NoiseSource>.allocate(capacity: 1)
    private let stateR = UnsafeMutablePointer<NoiseSource>.allocate(capacity: 1)

    public init() {
        eq = AVAudioUnitEQ(numberOfBands: AudioEngineModule.bandFrequencies.count)
        for (i, f) in AudioEngineModule.bandFrequencies.enumerated() {
            let band = eq.bands[i]
            band.filterType = .parametric
            band.frequency = f
            band.bandwidth = 1.0       // ~1 octave
            band.gain = 0
            band.bypass = false
        }

        stateL.initialize(to: NoiseSource(seed: 0x1234_5678_9ABC_DEF0))
        stateR.initialize(to: NoiseSource(seed: 0x0FED_CBA9_8765_4321))

        let l = stateL, r = stateR
        sourceNode = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                for (ch, buffer) in abl.enumerated() {
                    let ptr = buffer.mData!.assumingMemoryBound(to: Float.self)
                    let sample = (ch == 0) ? l.pointee.next() : r.pointee.next()
                    ptr[frame] = sample
                }
            }
            return noErr
        }

        engine.attach(sourceNode)
        engine.attach(eq)
        let format = engine.outputNode.inputFormat(forBus: 0)
        engine.connect(sourceNode, to: eq, format: format)
        engine.connect(eq, to: engine.mainMixerNode, format: format)
    }

    deinit {
        stateL.deinitialize(count: 1); stateL.deallocate()
        stateR.deinitialize(count: 1); stateR.deallocate()
    }

    public var bandCount: Int { eq.bands.count }

    public func centerFrequency(band: Int) -> Float { eq.bands[band].frequency }

    public func setGain(band: Int, dB: Float) {
        eq.bands[band].gain = min(12, max(-24, dB))
    }

    public func gain(band: Int) -> Float { eq.bands[band].gain }

    public func apply(_ preset: NoisePreset) {
        for (i, g) in preset.gains.enumerated() where i < eq.bands.count {
            eq.bands[i].gain = g
        }
    }

    public func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        if !engine.isRunning { try engine.start() }
    }

    public func stop() {
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -workspace Sculptor.xcworkspace -scheme AudioEngine -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add AudioEngine/Sources/NoiseEngine.swift AudioEngine/Tests/NoiseEngineTests.swift
git commit -m "feat: NoiseEngine audio graph with 8-band EQ"
```

---

### Task 5: Spike UI (8 sliders + preset buttons + play/pause)

**Files:**
- Create: `Sculptor/Sources/SpikeViewModel.swift`
- Modify: `Sculptor/Sources/RootView.swift`
- Test: none (UI glue — validated by the smoke run in Task 6)

**Interfaces:**
- Consumes: `NoiseEngine`, `NoisePreset` (Task 4 / Task 3).
- Produces: `RootView` rendering the spike screen.

- [ ] **Step 1: Write the view model**

`Sculptor/Sources/SpikeViewModel.swift`:
```swift
import SwiftUI
import AudioEngine

@MainActor
final class SpikeViewModel: ObservableObject {
    @Published var isPlaying = false
    @Published var gains: [Float]
    @Published var errorText: String?

    let frequencies: [Float] = [60, 125, 250, 500, 1000, 2000, 4000, 8000]
    private let engine = NoiseEngine()

    init() {
        gains = [Float](repeating: 0, count: 8)
    }

    func togglePlay() {
        if isPlaying {
            engine.stop()
            isPlaying = false
        } else {
            do { try engine.start(); isPlaying = true }
            catch { errorText = error.localizedDescription }
        }
    }

    func setGain(band: Int, dB: Float) {
        gains[band] = dB
        engine.setGain(band: band, dB: dB)
    }

    func apply(_ preset: NoisePreset) {
        engine.apply(preset)
        gains = preset.gains
    }
}
```

- [ ] **Step 2: Replace `RootView.swift`**

`Sculptor/Sources/RootView.swift`:
```swift
import SwiftUI
import AudioEngine

struct RootView: View {
    @StateObject private var vm = SpikeViewModel()

    var body: some View {
        VStack(spacing: 24) {
            Text("Phase 0 — Noise Spike").font(.headline)

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<8, id: \.self) { i in
                    VStack {
                        Slider(
                            value: Binding(
                                get: { vm.gains[i] },
                                set: { vm.setGain(band: i, dB: $0) }
                            ),
                            in: -24...12
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 120, height: 30)
                        .frame(maxHeight: 160)
                        Text(label(vm.frequencies[i])).font(.caption2)
                    }
                }
            }
            .frame(height: 220)

            HStack(spacing: 12) {
                Button("White") { vm.apply(.white) }
                Button("Pink") { vm.apply(.pink) }
                Button("Brown") { vm.apply(.brown) }
            }
            .buttonStyle(.bordered)

            Button(vm.isPlaying ? "Pause" : "Play") { vm.togglePlay() }
                .font(.title)
                .buttonStyle(.borderedProminent)

            if let err = vm.errorText {
                Text(err).font(.footnote).foregroundStyle(.red)
            }
        }
        .padding()
    }

    private func label(_ f: Float) -> String {
        f >= 1000 ? "\(Int(f / 1000))k" : "\(Int(f))"
    }
}
```

- [ ] **Step 3: Build the app**

Run: `xcodebuild -workspace Sculptor.xcworkspace -scheme Sculptor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Sculptor/Sources/SpikeViewModel.swift Sculptor/Sources/RootView.swift
git commit -m "feat: spike UI with 8 band sliders and preset buttons"
```

---

### Task 6: Simulator smoke run + device handoff

**Files:** none (verification task).

**Interfaces:**
- Consumes: the built `Sculptor` app.
- Produces: a running app on the simulator and a documented manual gate.

- [ ] **Step 1: Boot the simulator (if not booted)**

Run: `xcrun simctl boot "iPhone 17 Pro" 2>/dev/null; open -a Simulator`
Expected: simulator window appears.

- [ ] **Step 2: Build for the simulator and capture the app path**

Run:
```bash
xcodebuild -workspace Sculptor.xcworkspace -scheme Sculptor \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build build
```
Expected: `** BUILD SUCCEEDED **`; app at `build/Build/Products/Debug-iphonesimulator/Sculptor.app`.

- [ ] **Step 3: Install and launch**

Run:
```bash
xcrun simctl install "iPhone 17 Pro" build/Build/Products/Debug-iphonesimulator/Sculptor.app
xcrun simctl launch "iPhone 17 Pro" com.sculptor.app
```
Expected: app launches, no crash. Tapping Play starts audio (Mac plays sim audio); sliders and White/Pink/Brown change the timbre.

- [ ] **Step 4: Document the manual gate**

The real go/no-go is NOT the simulator. Confirm with the user:
- Run on a real device with headphones.
- Judge: is the noise clean (no clicks/aliasing/digital fizz)? Do White/Pink/Brown sound right? Are the sliders pleasant to sculpt?
- Decision: PASS → proceed to Phase 1 (designed Sculpt screen). FAIL → revisit synthesis (distribution, EQ bandwidth, sample rate) before any UI work.

- [ ] **Step 5: Commit any tweaks made during smoke testing** (if none, skip)

```bash
git add -A
git commit -m "chore: phase 0 smoke-test adjustments"
```
