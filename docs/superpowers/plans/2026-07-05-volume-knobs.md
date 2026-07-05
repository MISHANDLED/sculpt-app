# Volume Knobs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Home's two volume slider rows with two circular glow-ring knobs (NOISE = app gain, PHONE = system volume), styled per the approved spec.

**Architecture:** `KnobGeometry` (pure math) + `VolumeKnob` (SwiftUI view) live in DesignSystem. `SystemVolume` (KVO read of `AVAudioSession.outputVolume`, write via hidden `MPVolumeView`'s `UISlider`) lives in Sculptor and replaces `SystemVolumeSlider`. HomeView swaps its two HStack rows for one HStack of two knobs.

**Tech Stack:** SwiftUI, MediaPlayer (MPVolumeView), AVFoundation (outputVolume KVO), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-07-05-volume-knobs-design.md`

## Global Constraints

- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`), NOT XCTest.
- Tests never call `engine.start()` or `AVAudioSession.setActive(true)`.
- SourceKit diagnostics are false positives; `xcodebuild` is ground truth.
- xcodebuild output MUST redirect to a log file. Commands:
  - DesignSystem-only quick check not available as scheme; use full suite or Sculptor scheme.
  - Full suite: `xcodebuild test -workspace Sculptor.xcworkspace -scheme Sculptor-Workspace -destination 'platform=iOS Simulator,name=iPhone Air' > /tmp/knob-full.log 2>&1; echo "exit=$?"; tail -20 /tmp/knob-full.log`
- NEW FILES → run `tuist generate --no-open` BEFORE the RED run (stale project silently skips them).
- Commits on master, Sculptor identity: `git -c user.name='Sculptor' -c user.email='dev@sculptor.local' commit -m "..."`. No branch, no push.
- 270° sweep, gap centered at bottom. No `%` symbol anywhere. SF Symbols only (`speaker.wave.2.fill`, `iphone`), no emoji.
- Angle convention (everywhere): degrees, 0 at 12 o'clock, clockwise positive, sweep runs −135°…+135°.

---

### Task 1: KnobGeometry (DesignSystem, pure math)

**Files:**
- Create: `DesignSystem/Sources/Components/KnobGeometry.swift`
- Test: `DesignSystem/Tests/KnobGeometryTests.swift`

**Interfaces:**
- Produces: `public enum KnobGeometry` with:
  - `static let sweepDegrees: Float = 270`
  - `static func value(forAngle deg: Float) -> Float` — clamped 0…1; angles in the bottom gap clamp to nearest end
  - `static func angle(forValue v: Float) -> Float` — −135…135
  - `static func trimFraction(forValue v: Float) -> CGFloat` — 0…0.75 (for `Circle().trim`)
  - `static func touchAngle(location: CGPoint, center: CGPoint) -> Float` — clockwise-from-top degrees in −180…180

- [ ] **Step 1: Write failing tests**

Create `DesignSystem/Tests/KnobGeometryTests.swift`:

```swift
import Testing
import CoreGraphics
@testable import DesignSystem

@Suite("Knob geometry")
struct KnobGeometryTests {
    @Test func sweepEndsMapToZeroAndOne() {
        #expect(KnobGeometry.value(forAngle: -135) == 0)
        #expect(KnobGeometry.value(forAngle: 135) == 1)
    }

    @Test func topOfDialIsHalf() {
        #expect(abs(KnobGeometry.value(forAngle: 0) - 0.5) < 0.0001)
    }

    @Test func gapAnglesClampToNearestEnd() {
        #expect(KnobGeometry.value(forAngle: 170) == 1)   // past end, in gap
        #expect(KnobGeometry.value(forAngle: -170) == 0)  // before start, in gap
        #expect(KnobGeometry.value(forAngle: 180) == 1)   // dead bottom counts as high side
    }

    @Test func angleForValueRoundTrips() {
        #expect(KnobGeometry.angle(forValue: 0) == -135)
        #expect(KnobGeometry.angle(forValue: 1) == 135)
        #expect(abs(KnobGeometry.angle(forValue: 0.5)) < 0.0001)
        #expect(KnobGeometry.angle(forValue: -0.5) == -135) // clamps input
        #expect(KnobGeometry.angle(forValue: 2) == 135)
    }

    @Test func trimFractionIsThreeQuartersOfValue() {
        #expect(KnobGeometry.trimFraction(forValue: 0) == 0)
        #expect(KnobGeometry.trimFraction(forValue: 0.5) == 0.375)
        #expect(KnobGeometry.trimFraction(forValue: 1) == 0.75)
    }

    @Test func touchAngleCardinalPoints() {
        let c = CGPoint(x: 100, y: 100)
        // straight up from center = 0°
        #expect(abs(KnobGeometry.touchAngle(location: CGPoint(x: 100, y: 40), center: c)) < 0.0001)
        // right = +90°, left = -90°
        #expect(abs(KnobGeometry.touchAngle(location: CGPoint(x: 160, y: 100), center: c) - 90) < 0.0001)
        #expect(abs(KnobGeometry.touchAngle(location: CGPoint(x: 40, y: 100), center: c) + 90) < 0.0001)
    }
}
```

- [ ] **Step 2: `tuist generate --no-open`, then run to verify RED**

Run the full-suite command from Global Constraints. Expected: BUILD FAILURE — `KnobGeometry` undefined.

- [ ] **Step 3: Implement**

Create `DesignSystem/Sources/Components/KnobGeometry.swift`:

```swift
import CoreGraphics
import Foundation

/// Pure math for the 270° volume knob. Angle convention: degrees, 0 at
/// 12 o'clock, clockwise positive; the sweep runs -135°…+135° with the
/// gap centered at the bottom.
public enum KnobGeometry {
    public static let sweepDegrees: Float = 270
    private static let halfSweep: Float = 135

    /// Maps a clockwise-from-top angle to a 0…1 value. Angles inside the
    /// bottom gap clamp to the nearest sweep end (no wrap-around).
    public static func value(forAngle deg: Float) -> Float {
        let clamped = min(halfSweep, max(-halfSweep, deg))
        return (clamped + halfSweep) / sweepDegrees
    }

    /// Inverse of value(forAngle:), clamping the input to 0…1.
    public static func angle(forValue v: Float) -> Float {
        let clamped = min(1, max(0, v))
        return clamped * sweepDegrees - halfSweep
    }

    /// Fraction of the full circle the glow arc covers, for Circle().trim.
    public static func trimFraction(forValue v: Float) -> CGFloat {
        CGFloat(min(1, max(0, v))) * 0.75
    }

    /// Clockwise-from-top angle of a touch point around the knob center,
    /// in -180…180.
    public static func touchAngle(location: CGPoint, center: CGPoint) -> Float {
        let dx = Float(location.x - center.x)
        let dy = Float(location.y - center.y)
        return atan2(dx, -dy) * 180 / .pi
    }
}
```

- [ ] **Step 4: Run to verify GREEN**

Full-suite command. Expected: exit=0, `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add DesignSystem/Sources/Components/KnobGeometry.swift DesignSystem/Tests/KnobGeometryTests.swift
git -c user.name='Sculptor' -c user.email='dev@sculptor.local' commit -m "feat: knob geometry math for circular volume control"
```

---

### Task 2: VolumeKnob view (DesignSystem)

**Files:**
- Create: `DesignSystem/Sources/Components/VolumeKnob.swift`

**Interfaces:**
- Consumes: `KnobGeometry` from Task 1 (exact signatures above).
- Produces: `public struct VolumeKnob: View`, init `public init(value: Binding<Float>, icon: String, label: String)`.

No unit test (declarative view; all logic already tested in KnobGeometry). Verify by building.

- [ ] **Step 1: Implement**

Create `DesignSystem/Sources/Components/VolumeKnob.swift`:

```swift
import SwiftUI

/// Circular DJ-style volume control: dark 270° track with a glowing accent
/// arc and tip dot. Shows an SF Symbol at rest and the bare 0–100 value
/// while the finger is down. Circular drag only.
public struct VolumeKnob: View {
    @Binding var value: Float
    let icon: String
    let label: String

    @State private var isDragging = false
    @State private var lastValue: Float = -1

    private let size: CGFloat = 110
    private let trackWidth: CGFloat = 8

    public init(value: Binding<Float>, icon: String, label: String) {
        _value = value
        self.icon = icon
        self.label = label
    }

    public var body: some View {
        VStack(spacing: DockSpacing.sm) {
            ZStack {
                arc(to: 0.75, color: DockColor.surface3)
                arc(to: KnobGeometry.trimFraction(forValue: value), color: DockColor.accent)
                    .shadow(color: DockColor.accent.opacity(0.55), radius: 6)
                tipDot
                centerReadout
            }
            .frame(width: size, height: size)
            .contentShape(Circle().inset(by: -trackWidth))
            .gesture(dragGesture)
            Text(label)
                .font(DockType.font(11))
                .kerning(2.5)
                .foregroundStyle(DockColor.textTertiary)
        }
    }

    private func arc(to trim: CGFloat, color: Color) -> some View {
        Circle()
            .trim(from: 0, to: trim)
            .stroke(color, style: StrokeStyle(lineWidth: trackWidth, lineCap: .round))
            // trim 0 sits at 3 o'clock; +135° puts it at the sweep start (7:30).
            .rotationEffect(.degrees(135))
    }

    private var tipDot: some View {
        let angle = Double(KnobGeometry.angle(forValue: value))
        return Circle()
            .fill(Color.white)
            .frame(width: 10, height: 10)
            .shadow(color: DockColor.accent, radius: 4)
            .offset(y: -size / 2)
            .rotationEffect(.degrees(angle))
    }

    @ViewBuilder private var centerReadout: some View {
        if isDragging {
            Text("\(Int((value * 100).rounded()))")
                .font(DockType.font(30))
                .fontWeight(.semibold)
                .foregroundStyle(DockColor.textPrimary)
        } else {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(DockColor.accent)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                isDragging = true
                let center = CGPoint(x: size / 2, y: size / 2)
                let angle = KnobGeometry.touchAngle(location: g.location, center: center)
                let newValue = KnobGeometry.value(forAngle: angle)
                if (newValue == 0 || newValue == 1), lastValue != newValue {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                lastValue = newValue
                value = newValue
            }
            .onEnded { _ in
                isDragging = false
                lastValue = -1
            }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Full-suite command (build implies compile of DesignSystem). Expected: exit=0, `** TEST SUCCEEDED **` (same test counts as Task 1 — no new tests).

- [ ] **Step 3: Commit**

```bash
git add DesignSystem/Sources/Components/VolumeKnob.swift
git -c user.name='Sculptor' -c user.email='dev@sculptor.local' commit -m "feat: VolumeKnob glow-ring control"
```

---

### Task 3: SystemVolume (Sculptor) — read via KVO, write via hidden MPVolumeView

**Files:**
- Create: `Sculptor/Sources/SystemVolume.swift`
- Test: `Sculptor/Tests/SystemVolumeTests.swift`
- Delete: `Sculptor/Sources/SystemVolumeSlider.swift`, `Sculptor/Tests/SystemVolumeSliderTests.swift`

**Interfaces:**
- Produces:
  - `@MainActor final class SystemVolume: ObservableObject` with `@Published private(set) var level: Float`, `func setLevel(_ v: Float)`, `let volumeView: MPVolumeView` (the hidden view a host must keep in the hierarchy)
  - `static func makeHiddenVolumeView() -> MPVolumeView`
  - `static func findSlider(in view: UIView) -> UISlider?`
  - `struct HiddenVolumeHost: UIViewRepresentable` (init `HiddenVolumeHost(volume: SystemVolume)`) — embeds `volume.volumeView`

- [ ] **Step 1: Write failing tests**

Create `Sculptor/Tests/SystemVolumeTests.swift`:

```swift
import Testing
import UIKit
import MediaPlayer
@testable import Sculptor

@Suite("System volume plumbing")
@MainActor
struct SystemVolumeTests {
    @Test func hiddenVolumeViewIsInvisibleAndInert() {
        let v = SystemVolume.makeHiddenVolumeView()
        #expect(v.alpha < 0.02)
        #expect(v.isUserInteractionEnabled == false)
    }

    @Test func findSliderLocatesNestedSlider() {
        let root = UIView()
        let mid = UIView()
        let slider = UISlider()
        mid.addSubview(slider)
        root.addSubview(mid)
        #expect(SystemVolume.findSlider(in: root) === slider)
    }

    @Test func findSliderReturnsNilWhenAbsent() {
        let root = UIView()
        root.addSubview(UIView())
        #expect(SystemVolume.findSlider(in: root) == nil)
    }

    @Test func levelStartsAtSessionOutputVolume() {
        let sv = SystemVolume()
        #expect(sv.level == AVAudioSession.sharedInstance().outputVolume)
    }
}
```

Add `import AVFoundation` if `AVAudioSession` is not visible via MediaPlayer.

- [ ] **Step 2: Delete replaced files, regenerate, verify RED**

```bash
rm Sculptor/Sources/SystemVolumeSlider.swift Sculptor/Tests/SystemVolumeSliderTests.swift
tuist generate --no-open
```

Run full-suite command. Expected: BUILD FAILURE — `SystemVolume` undefined (and HomeView still references `SystemVolumeSlider`, which also fails — expected at RED; Task 4 removes that reference, but to keep THIS task green, apply the minimal HomeView change now: delete lines forming the `SystemVolumeSlider` HStack row, i.e. the `HStack` containing `Image(systemName: "iphone")` and `SystemVolumeSlider()`; leave the master-volume Slider row alone — Task 4 replaces it).

- [ ] **Step 3: Implement**

Create `Sculptor/Sources/SystemVolume.swift`:

```swift
import AVFoundation
import MediaPlayer
import SwiftUI

/// System (hardware) volume bridge. Reads via KVO on the audio session's
/// outputVolume; writes via the UISlider inside a hidden MPVolumeView —
/// the only sanctioned way to set system volume. If iOS ever stops
/// exposing that slider, setLevel degrades to a no-op and the knob
/// becomes display-only.
@MainActor
final class SystemVolume: ObservableObject {
    @Published private(set) var level: Float

    /// Host must keep this view in the window hierarchy for setLevel to work.
    let volumeView = SystemVolume.makeHiddenVolumeView()

    private var observation: NSKeyValueObservation?

    init() {
        let session = AVAudioSession.sharedInstance()
        level = session.outputVolume
        observation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let v = change.newValue else { return }
            Task { @MainActor [weak self] in self?.level = v }
        }
    }

    func setLevel(_ v: Float) {
        let clamped = min(1, max(0, v))
        level = clamped
        Self.findSlider(in: volumeView)?.value = clamped
    }

    static func makeHiddenVolumeView() -> MPVolumeView {
        let v = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        v.alpha = 0.01          // 0 can make iOS skip layout of the slider
        v.isUserInteractionEnabled = false
        v.clipsToBounds = true
        return v
    }

    static func findSlider(in view: UIView) -> UISlider? {
        if let slider = view as? UISlider { return slider }
        for sub in view.subviews {
            if let found = findSlider(in: sub) { return found }
        }
        return nil
    }
}

/// Keeps the hidden MPVolumeView alive in the hierarchy behind Home.
struct HiddenVolumeHost: UIViewRepresentable {
    let volume: SystemVolume

    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: .zero)
        container.addSubview(volume.volumeView)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
```

- [ ] **Step 4: Run to verify GREEN**

Full-suite command. Expected: exit=0, `** TEST SUCCEEDED **`, new SystemVolumeTests passing, SystemVolumeSliderTests gone.

- [ ] **Step 5: Commit**

```bash
git add -A Sculptor/Sources Sculptor/Tests
git -c user.name='Sculptor' -c user.email='dev@sculptor.local' commit -m "feat: SystemVolume KVO bridge replacing SystemVolumeSlider"
```

---

### Task 4: HomeView integration + final verification

**Files:**
- Modify: `Sculptor/Sources/HomeView.swift` (`heroCenter`, currently lines ~90–122)

**Interfaces:**
- Consumes: `VolumeKnob(value:icon:label:)` (Task 2), `SystemVolume` / `HiddenVolumeHost` (Task 3), existing `vm.masterVolume`.

- [ ] **Step 1: Replace the volume rows**

In `HomeView`, add state next to the existing `@Bindable`/`vm` property:

```swift
    @StateObject private var systemVolume = SystemVolume()
```

Replace the master-volume `HStack` row (the one wrapping `Slider(value: $vm.masterVolume, in: 0...1)`; the `SystemVolumeSlider` row was already removed in Task 3) with:

```swift
            HStack(spacing: DockSpacing.xl * 2) {
                VolumeKnob(value: $vm.masterVolume, icon: "speaker.wave.2.fill", label: "NOISE")
                VolumeKnob(
                    value: Binding(
                        get: { systemVolume.level },
                        set: { systemVolume.setLevel($0) }
                    ),
                    icon: "iphone",
                    label: "PHONE"
                )
            }
            .padding(.top, DockSpacing.sm)
            .background(HiddenVolumeHost(volume: systemVolume).frame(width: 1, height: 1))
```

- [ ] **Step 2: Run full suite**

Full-suite command. Expected: exit=0, `** TEST SUCCEEDED **`.

- [ ] **Step 3: Sim smoke — knobs render**

```bash
xcodebuild -workspace Sculptor.xcworkspace -scheme Sculptor -destination 'platform=iOS Simulator,name=iPhone Air' build > /tmp/knob-sim.log 2>&1; echo "exit=$?"; tail -3 /tmp/knob-sim.log
```

Expected: BUILD SUCCEEDED. (Controller handles install/screenshot; PHONE knob is inert on sim — device-only.)

- [ ] **Step 4: Commit**

```bash
git add Sculptor/Sources/HomeView.swift
git -c user.name='Sculptor' -c user.email='dev@sculptor.local' commit -m "feat: replace volume sliders with NOISE and PHONE knobs"
```
