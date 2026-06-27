# Phase 1A — DesignSystem + Sculpt Screen + Audio Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Phase-0 spike UI with a designed Sculpt screen backed by a reusable `DesignSystem` framework, and harden `AudioEngine` for real-world playback.

**Architecture:** New Tuist framework `DesignSystem` (pure visual layer: Dock tokens, Lexend fonts, dumb SwiftUI components) sits beside the existing `AudioEngine` framework. The `Sculptor` app composes both — a `SculptViewModel` binds `DesignSystem` views to `AudioEngine`. `AudioEngine` gains an explicit render format and AVAudioSession interruption/route handling.

**Tech Stack:** Swift 6, SwiftUI, AVFoundation, Tuist 4.x, Swift Testing (`import Testing`).

## Global Constraints

- iOS 17.0 deployment floor.
- Tuist-only project generation — never hand-edit `.xcodeproj`/`.xcworkspace` (gitignored, regenerated via `tuist generate`).
- Band frequencies (fixed, 8 bands): `60, 125, 250, 500, 1000, 2000, 4000, 8000` Hz.
- Gain range: `-24 … +12` dB, clamped in `NoiseEngine.setGain`.
- RT-safe render callback: no locks, heap allocation, ARC, or `self` capture on the audio thread.
- Bundle id prefix `com.sculptor` (new framework: `com.sculptor.designsystem`).
- Dark theme only.
- All tests via Swift Testing (`import Testing`, `@Test`, `#expect`). Test output must be pristine (no stray warnings/logs).

## File Structure

**DesignSystem (new framework):**
- `DesignSystem/Sources/Tokens/DockColor.swift` — semantic colors + hex decode helper.
- `DesignSystem/Sources/Tokens/DockMetrics.swift` — `DockSpacing`, `DockRadius` constants.
- `DesignSystem/Sources/Tokens/DockType.swift` — Lexend `Font` helpers.
- `DesignSystem/Sources/Fonts/FontRegistrar.swift` — registers bundled `.ttf`.
- `DesignSystem/Sources/Components/BandSlider.swift` — vertical slider + pure `bandSliderFillFraction`.
- `DesignSystem/Sources/Components/PresetChip.swift` — selectable pill.
- `DesignSystem/Sources/Components/DockCard.swift` — surface container.
- `DesignSystem/Sources/Components/DockButton.swift` — primary/secondary button style.
- `DesignSystem/Resources/Fonts/*.ttf` — 5 Lexend weights (added Task 3).
- `DesignSystem/Tests/*.swift` — token/font/component-logic tests.

**AudioEngine (modify):**
- `AudioEngine/Sources/NoisePreset.swift` — add `.grey`, `.speechBlocker`.
- `AudioEngine/Sources/NoiseEngine.swift` — explicit format, interruption/route handling.
- `AudioEngine/Sources/AudioSessionPolicy.swift` (new) — pure interruption/route → action mappers.
- `AudioEngine/Tests/` — new tests for the above.

**Sculptor (modify):**
- `Sculptor/Sources/SculptViewModel.swift` (new, replaces `SpikeViewModel.swift`).
- `Sculptor/Sources/SculptView.swift` (new, replaces `RootView.swift`).
- `Sculptor/Sources/SculptorApp.swift` — root `SculptView`.

**Project:**
- `Project.swift` — add `DesignSystem` + `DesignSystemTests` targets; add `DesignSystem` dep to `Sculptor`.

---

### Task 1: Add DesignSystem framework target to Tuist

**Files:**
- Modify: `Project.swift`
- Create: `DesignSystem/Sources/DesignSystem.swift`
- Create: `DesignSystem/Tests/SmokeTests.swift`

**Interfaces:**
- Produces: `DesignSystem` framework module (importable), `DesignSystemTests` target.

- [ ] **Step 1: Add the targets to `Project.swift`**

Insert these two targets into the `targets:` array (after `AudioEngineTests`, before `Sculptor`), and add the `DesignSystem` dependency to the existing `Sculptor` target.

```swift
        .target(
            name: "DesignSystem",
            destinations: .iOS,
            product: .framework,
            bundleId: "com.sculptor.designsystem",
            deploymentTargets: .iOS("17.0"),
            sources: ["DesignSystem/Sources/**"],
            dependencies: []
        ),
        .target(
            name: "DesignSystemTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.sculptor.designsystem.tests",
            deploymentTargets: .iOS("17.0"),
            sources: ["DesignSystem/Tests/**"],
            dependencies: [.target(name: "DesignSystem")]
        ),
```

Change the `Sculptor` target's `dependencies` from:
```swift
            dependencies: [.target(name: "AudioEngine")]
```
to:
```swift
            dependencies: [
                .target(name: "AudioEngine"),
                .target(name: "DesignSystem")
            ]
```

- [ ] **Step 2: Create a placeholder source file** (so the framework has something to compile)

`DesignSystem/Sources/DesignSystem.swift`:
```swift
// DesignSystem — Dock/Blinkit visual layer for Sculptor.
// Tokens, fonts, and reusable SwiftUI components live in this framework.
```

- [ ] **Step 3: Create a smoke test**

`DesignSystem/Tests/SmokeTests.swift`:
```swift
import Testing
@testable import DesignSystem

@Test func moduleImports() {
    #expect(Bool(true))
}
```

- [ ] **Step 4: Regenerate the project and build**

Run: `tuist generate --no-open && xcodebuild build -workspace Sculptor.xcworkspace -scheme DesignSystem -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add Project.swift DesignSystem/Sources/DesignSystem.swift DesignSystem/Tests/SmokeTests.swift
git commit -m "feat: add DesignSystem framework target"
```

---

### Task 2: Color & metric tokens

**Files:**
- Create: `DesignSystem/Sources/Tokens/DockColor.swift`
- Create: `DesignSystem/Sources/Tokens/DockMetrics.swift`
- Create: `DesignSystem/Tests/DockColorTests.swift`

**Interfaces:**
- Produces: `DockColor` (static `Color`s: `accent`, `background`, `surface1/2/3`, `textPrimary/Secondary/Tertiary`, `border`); internal `dockRGB(hex:) -> (Double, Double, Double)`; `DockSpacing` (`xs/sm/md/lg/xl` = 4/8/12/16/24); `DockRadius` (`card` = 16, `chip` = 12).

- [ ] **Step 1: Write the failing test**

`DesignSystem/Tests/DockColorTests.swift`:
```swift
import Testing
@testable import DesignSystem

@Test func decodesAccentTeal() {
    let (r, g, b) = dockRGB(hex: 0x2ED3B7)
    #expect(abs(r - 0x2E / 255.0) < 0.001)
    #expect(abs(g - 0xD3 / 255.0) < 0.001)
    #expect(abs(b - 0xB7 / 255.0) < 0.001)
}

@Test func decodesBlackBackground() {
    let (r, g, b) = dockRGB(hex: 0x0D0D11)
    #expect(abs(r - 0x0D / 255.0) < 0.001)
    #expect(abs(g - 0x0D / 255.0) < 0.001)
    #expect(abs(b - 0x11 / 255.0) < 0.001)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -workspace Sculptor.xcworkspace -scheme DesignSystem -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:DesignSystemTests/DockColorTests`
Expected: FAIL — `dockRGB` not defined.

- [ ] **Step 3: Implement `DockColor.swift`**

```swift
import SwiftUI

/// Decodes a 0xRRGGBB integer into sRGB components in 0...1.
func dockRGB(hex: UInt32) -> (Double, Double, Double) {
    let r = Double((hex >> 16) & 0xFF) / 255.0
    let g = Double((hex >> 8) & 0xFF) / 255.0
    let b = Double(hex & 0xFF) / 255.0
    return (r, g, b)
}

private extension Color {
    init(dockHex hex: UInt32) {
        let (r, g, b) = dockRGB(hex: hex)
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

/// Semantic Dock dark-theme colors. Source: colors_and_type.css (dark theme).
public enum DockColor {
    public static let accent        = Color(dockHex: 0x2ED3B7) // teal-400
    public static let background    = Color(dockHex: 0x0D0D11) // black-dark
    public static let surface1      = Color(dockHex: 0x17171C) // grey-dark-900
    public static let surface2      = Color(dockHex: 0x202027) // grey-dark-800
    public static let surface3      = Color(dockHex: 0x2F2F37) // grey-dark-700
    public static let textPrimary   = Color(dockHex: 0xFAFAFA) // grey-dark-50
    public static let textSecondary = Color(dockHex: 0xCACACE) // grey-dark-300
    public static let textTertiary  = Color(dockHex: 0x95959D) // grey-dark-400
    public static let border        = Color(dockHex: 0x2F2F37) // grey-dark-700
}
```

- [ ] **Step 4: Implement `DockMetrics.swift`**

```swift
import CoreGraphics

public enum DockSpacing {
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 24
}

public enum DockRadius {
    public static let chip: CGFloat = 12
    public static let card: CGFloat = 16
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -workspace Sculptor.xcworkspace -scheme DesignSystem -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:DesignSystemTests/DockColorTests`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add DesignSystem/Sources/Tokens/DockColor.swift DesignSystem/Sources/Tokens/DockMetrics.swift DesignSystem/Tests/DockColorTests.swift
git commit -m "feat: add Dock color and metric tokens"
```

---

### Task 3: Bundle + register Lexend fonts, add DockType

**Files:**
- Create: `DesignSystem/Resources/Fonts/` (copy 5 Lexend `.ttf`)
- Modify: `Project.swift` (add `resources` to DesignSystem target)
- Create: `DesignSystem/Sources/Fonts/FontRegistrar.swift`
- Create: `DesignSystem/Sources/Tokens/DockType.swift`
- Create: `DesignSystem/Tests/FontTests.swift`

**Interfaces:**
- Produces: `FontRegistrar.registerFonts()` (idempotent, registers bundled Lexend faces); `DockType.lexendFontName(for:) -> String` (pure weight→PostScript-name map); `DockType.font(_ size:CGFloat, _ weight:DockType.Weight) -> Font`; `DockType.Weight` enum (`.light/.regular/.medium/.semibold/.bold`).

- [ ] **Step 1: Copy the font files into the framework resources**

Run:
```bash
mkdir -p DesignSystem/Resources/Fonts
cp "sculptor_design/_ds/dock-design-system-019e2612-6886-790a-8cb5-ffa17f42f6ed/fonts/Lexend-Light.ttf" \
   "sculptor_design/_ds/dock-design-system-019e2612-6886-790a-8cb5-ffa17f42f6ed/fonts/Lexend-Regular.ttf" \
   "sculptor_design/_ds/dock-design-system-019e2612-6886-790a-8cb5-ffa17f42f6ed/fonts/Lexend-Medium.ttf" \
   "sculptor_design/_ds/dock-design-system-019e2612-6886-790a-8cb5-ffa17f42f6ed/fonts/Lexend-SemiBold.ttf" \
   "sculptor_design/_ds/dock-design-system-019e2612-6886-790a-8cb5-ffa17f42f6ed/fonts/Lexend-Bold.ttf" \
   DesignSystem/Resources/Fonts/
```

- [ ] **Step 2: Declare resources in `Project.swift`**

In the `DesignSystem` target, add a `resources` parameter after `sources`:
```swift
            sources: ["DesignSystem/Sources/**"],
            resources: ["DesignSystem/Resources/**"],
            dependencies: []
```

- [ ] **Step 3: Write the failing test**

`DesignSystem/Tests/FontTests.swift`:
```swift
import Testing
import UIKit
@testable import DesignSystem

@Test func weightMapsToPostScriptName() {
    #expect(DockType.lexendFontName(for: .regular) == "Lexend-Regular")
    #expect(DockType.lexendFontName(for: .bold) == "Lexend-Bold")
    #expect(DockType.lexendFontName(for: .semibold) == "Lexend-SemiBold")
}

@Test func registeredFontIsResolvable() {
    FontRegistrar.registerFonts()
    #expect(UIFont(name: "Lexend-Regular", size: 12) != nil)
    #expect(UIFont(name: "Lexend-Bold", size: 12) != nil)
}
```

- [ ] **Step 4: Run test to verify it fails**

Run: `tuist generate --no-open && xcodebuild test -workspace Sculptor.xcworkspace -scheme DesignSystem -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:DesignSystemTests/FontTests`
Expected: FAIL — `DockType` / `FontRegistrar` not defined.

- [ ] **Step 5: Implement `FontRegistrar.swift`**

```swift
import CoreText
import Foundation

public enum FontRegistrar {
    private static var didRegister = false

    /// Registers all bundled Lexend faces with the font manager. Idempotent.
    public static func registerFonts() {
        guard !didRegister else { return }
        didRegister = true
        let names = ["Lexend-Light", "Lexend-Regular", "Lexend-Medium",
                     "Lexend-SemiBold", "Lexend-Bold"]
        for name in names {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf") else {
                assertionFailure("Missing bundled font: \(name).ttf")
                continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
```

- [ ] **Step 6: Implement `DockType.swift`**

```swift
import SwiftUI

public enum DockType {
    public enum Weight {
        case light, regular, medium, semibold, bold
    }

    /// Pure map from a semantic weight to the bundled font's PostScript name.
    public static func lexendFontName(for weight: Weight) -> String {
        switch weight {
        case .light:    return "Lexend-Light"
        case .regular:  return "Lexend-Regular"
        case .medium:   return "Lexend-Medium"
        case .semibold: return "Lexend-SemiBold"
        case .bold:     return "Lexend-Bold"
        }
    }

    /// A Lexend `Font` at the given point size and weight. Ensures fonts are registered.
    public static func font(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        FontRegistrar.registerFonts()
        return .custom(lexendFontName(for: weight), fixedSize: size)
    }
}
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `xcodebuild test -workspace Sculptor.xcworkspace -scheme DesignSystem -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:DesignSystemTests/FontTests`
Expected: PASS (2 tests).

- [ ] **Step 8: Commit**

```bash
git add Project.swift DesignSystem/Resources DesignSystem/Sources/Fonts/FontRegistrar.swift DesignSystem/Sources/Tokens/DockType.swift DesignSystem/Tests/FontTests.swift
git commit -m "feat: bundle and register Lexend fonts, add DockType"
```

---

### Task 4: BandSlider component

**Files:**
- Create: `DesignSystem/Sources/Components/BandSlider.swift`
- Create: `DesignSystem/Tests/BandSliderTests.swift`

**Interfaces:**
- Consumes: `DockColor`.
- Produces: `bandSliderFillFraction(value: Float, in: ClosedRange<Float>) -> CGFloat` (clamped 0...1); `BandSlider` view (`init(value: Binding<Float>, range: ClosedRange<Float>)`).

- [ ] **Step 1: Write the failing test**

`DesignSystem/Tests/BandSliderTests.swift`:
```swift
import Testing
@testable import DesignSystem

@Test func fillFractionAtMidpoint() {
    #expect(abs(bandSliderFillFraction(value: -6, in: -24...12) - 0.5) < 0.001)
}

@Test func fillFractionClampsAboveAndBelow() {
    #expect(bandSliderFillFraction(value: 100, in: -24...12) == 1)
    #expect(bandSliderFillFraction(value: -100, in: -24...12) == 0)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -workspace Sculptor.xcworkspace -scheme DesignSystem -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:DesignSystemTests/BandSliderTests`
Expected: FAIL — `bandSliderFillFraction` not defined.

- [ ] **Step 3: Implement `BandSlider.swift`**

```swift
import SwiftUI

/// Fraction (0...1) of the track that should be filled for `value` within `range`.
public func bandSliderFillFraction(value: Float, in range: ClosedRange<Float>) -> CGFloat {
    let clamped = min(range.upperBound, max(range.lowerBound, value))
    let span = range.upperBound - range.lowerBound
    guard span > 0 else { return 0 }
    return CGFloat((clamped - range.lowerBound) / span)
}

/// Vertical EQ slider: teal fill from the bottom with a glowing knob.
/// A dumb component — it knows nothing about frequency or audio.
public struct BandSlider: View {
    @Binding private var value: Float
    private let range: ClosedRange<Float>

    public init(value: Binding<Float>, range: ClosedRange<Float>) {
        self._value = value
        self.range = range
    }

    public var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let fraction = bandSliderFillFraction(value: value, in: range)
            let knobY = height * (1 - fraction)

            ZStack(alignment: .bottom) {
                // Track
                Capsule()
                    .fill(DockColor.surface3)
                    .frame(width: 4)
                // Fill
                Capsule()
                    .fill(DockColor.accent)
                    .frame(width: 4, height: height * fraction)
                // Knob
                Circle()
                    .fill(DockColor.accent)
                    .frame(width: 16, height: 16)
                    .shadow(color: DockColor.accent.opacity(0.7), radius: 8)
                    .position(x: geo.size.width / 2, y: knobY)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let f = 1 - min(1, max(0, g.location.y / height))
                        let span = range.upperBound - range.lowerBound
                        value = range.lowerBound + Float(f) * span
                    }
            )
        }
    }
}

#Preview {
    struct Demo: View {
        @State var v: Float = -6
        var body: some View {
            BandSlider(value: $v, range: -24...12)
                .frame(width: 40, height: 200)
                .padding()
                .background(DockColor.background)
        }
    }
    return Demo()
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -workspace Sculptor.xcworkspace -scheme DesignSystem -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:DesignSystemTests/BandSliderTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add DesignSystem/Sources/Components/BandSlider.swift DesignSystem/Tests/BandSliderTests.swift
git commit -m "feat: add BandSlider component"
```

---

### Task 5: PresetChip, DockCard, DockButton components

**Files:**
- Create: `DesignSystem/Sources/Components/PresetChip.swift`
- Create: `DesignSystem/Sources/Components/DockCard.swift`
- Create: `DesignSystem/Sources/Components/DockButton.swift`

**Interfaces:**
- Consumes: `DockColor`, `DockType`, `DockRadius`, `DockSpacing`.
- Produces:
  - `PresetChip` (`init(title: String, isSelected: Bool, action: @escaping () -> Void)`).
  - `DockCard<Content: View>` (`init(@ViewBuilder content: () -> Content)`).
  - `DockButton` (`init(title: String, style: DockButton.Style = .primary, action: @escaping () -> Void)`, `Style` = `.primary | .secondary`).

These are pure presentational views with no branching logic to unit-test; they are verified via `#Preview` and the Sculpt screen smoke test in Task 10. Do not add placeholder tests that assert nothing.

- [ ] **Step 1: Implement `PresetChip.swift`**

```swift
import SwiftUI

/// Selectable pill. Selected = teal fill; unselected = subtle surface + border.
public struct PresetChip: View {
    private let title: String
    private let isSelected: Bool
    private let action: () -> Void

    public init(title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(DockType.font(14, .medium))
                .foregroundStyle(isSelected ? DockColor.background : DockColor.textSecondary)
                .padding(.horizontal, DockSpacing.lg)
                .padding(.vertical, DockSpacing.sm)
                .background(
                    Capsule().fill(isSelected ? DockColor.accent : DockColor.surface2)
                )
                .overlay(
                    Capsule().stroke(isSelected ? DockColor.accent : DockColor.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    HStack {
        PresetChip(title: "White", isSelected: true) {}
        PresetChip(title: "Pink", isSelected: false) {}
    }
    .padding()
    .background(DockColor.background)
}
```

- [ ] **Step 2: Implement `DockCard.swift`**

```swift
import SwiftUI

/// Rounded surface container used to group controls.
public struct DockCard<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(DockSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: DockRadius.card)
                    .fill(DockColor.surface1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DockRadius.card)
                    .stroke(DockColor.border, lineWidth: 1)
            )
    }
}

#Preview {
    DockCard { Text("Card").foregroundStyle(DockColor.textPrimary) }
        .padding()
        .background(DockColor.background)
}
```

- [ ] **Step 3: Implement `DockButton.swift`**

```swift
import SwiftUI

/// Primary (teal) or secondary (surface) action button.
public struct DockButton: View {
    public enum Style { case primary, secondary }

    private let title: String
    private let style: Style
    private let action: () -> Void

    public init(title: String, style: Style = .primary, action: @escaping () -> Void) {
        self.title = title
        self.style = style
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(DockType.font(18, .semibold))
                .foregroundStyle(style == .primary ? DockColor.background : DockColor.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DockSpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: DockRadius.chip)
                        .fill(style == .primary ? DockColor.accent : DockColor.surface2)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack {
        DockButton(title: "Play") {}
        DockButton(title: "Pause", style: .secondary) {}
    }
    .padding()
    .background(DockColor.background)
}
```

- [ ] **Step 4: Build to verify it compiles**

Run: `xcodebuild build -workspace Sculptor.xcworkspace -scheme DesignSystem -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add DesignSystem/Sources/Components/PresetChip.swift DesignSystem/Sources/Components/DockCard.swift DesignSystem/Sources/Components/DockButton.swift
git commit -m "feat: add PresetChip, DockCard, DockButton components"
```

---

### Task 6: Grey + Speech-blocker presets

**Files:**
- Modify: `AudioEngine/Sources/NoisePreset.swift`
- Modify: `AudioEngine/Tests/NoisePresetTests.swift`

**Interfaces:**
- Produces: `NoisePreset.grey`, `NoisePreset.speechBlocker` (both yield 8 gains clamped to −24…+12).

- [ ] **Step 1: Write the failing tests** (append to `NoisePresetTests.swift`)

```swift
@Test func greyIsUShaped() {
    let g = NoisePreset.grey.gains
    #expect(g.count == 8)
    #expect(g.first! > g[3])   // low edge boosted above the mids
    #expect(g.last! > g[4])    // high edge boosted above the mids
}

@Test func speechBlockerBoostsMidBands() {
    let g = NoisePreset.speechBlocker.gains
    #expect(g.count == 8)
    #expect(g[3] > g.first!)   // 500 Hz boosted above the low edge
    #expect(g[4] > g.last!)    // 1 kHz boosted above the high edge
}

@Test func newPresetsAreClamped() {
    for p in [NoisePreset.grey, .speechBlocker] {
        for g in p.gains { #expect(g >= -24 && g <= 12) }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -workspace Sculptor.xcworkspace -scheme AudioEngine -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:AudioEngineTests/NoisePresetTests`
Expected: FAIL — `grey` / `speechBlocker` not members of `NoisePreset`.

- [ ] **Step 3: Rewrite `NoisePreset.swift`**

```swift
import Foundation

/// Built-in noise colors expressed as 8-band EQ tilts over white noise.
/// white/pink/brown are derived from a per-octave slope referenced to the
/// lowest band (60 Hz = 0 dB). grey/speechBlocker use explicit starter tables
/// (tune by ear later). All gains clamp to the engine's -24…+12 dB range.
public enum NoisePreset: CaseIterable {
    case white, pink, brown, grey, speechBlocker

    public var gains: [Float] {
        switch self {
        case .white, .pink, .brown:
            return tiltGains(slopePerOctave: slopePerOctave)
        case .grey:
            // U-shaped, approximating an inverse equal-loudness contour.
            return Self.clamp([6, 3, 0, -2, -2, 0, 4, 8])
        case .speechBlocker:
            // Energy concentrated in the speech band (~300–3000 Hz) to mask conversation.
            return Self.clamp([-8, -4, 3, 6, 6, 3, -4, -8])
        }
    }

    /// dB per octave of attenuation for the slope-derived colors.
    private var slopePerOctave: Float {
        switch self {
        case .white: return 0
        case .pink:  return 3
        case .brown: return 6
        case .grey, .speechBlocker: return 0   // unused (table-driven)
        }
    }

    private func tiltGains(slopePerOctave: Float) -> [Float] {
        let freqs = AudioEngineModule.bandFrequencies
        guard let base = freqs.first else { return [] }
        return freqs.map { f in
            let octaves = log2(f / base)
            return Self.clampOne(-slopePerOctave * octaves)
        }
    }

    private static func clamp(_ gains: [Float]) -> [Float] { gains.map(clampOne) }
    private static func clampOne(_ g: Float) -> Float { min(12, max(-24, g)) }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -workspace Sculptor.xcworkspace -scheme AudioEngine -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:AudioEngineTests/NoisePresetTests`
Expected: PASS (all existing + 3 new).

- [ ] **Step 5: Commit**

```bash
git add AudioEngine/Sources/NoisePreset.swift AudioEngine/Tests/NoisePresetTests.swift
git commit -m "feat: add grey and speech-blocker presets"
```

---

### Task 7: Explicit render format

**Files:**
- Modify: `AudioEngine/Sources/NoiseEngine.swift`
- Create: `AudioEngine/Tests/NoiseEngineFormatTests.swift`

**Interfaces:**
- Produces: `NoiseEngine.outputFormat: AVAudioFormat` (44.1 kHz, 2 channels, float32 non-interleaved) used to build the graph.

- [ ] **Step 1: Write the failing test**

`AudioEngine/Tests/NoiseEngineFormatTests.swift`:
```swift
import Testing
import AVFoundation
@testable import AudioEngine

@Test func usesExplicitStereo44kFormat() {
    let engine = NoiseEngine()
    #expect(engine.outputFormat.sampleRate == 44100)
    #expect(engine.outputFormat.channelCount == 2)
    #expect(engine.outputFormat.commonFormat == .pcmFormatFloat32)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -workspace Sculptor.xcworkspace -scheme AudioEngine -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:AudioEngineTests/NoiseEngineFormatTests`
Expected: FAIL — `outputFormat` not a member.

- [ ] **Step 3: Edit `NoiseEngine.swift`** — add the stored format and use it in the graph.

Add a stored property after `private let eq: AVAudioUnitEQ`:
```swift
    /// Explicit graph format. Built independently of the output node so the
    /// graph is valid before the audio session is active.
    let outputFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
```

Replace the three lines in `init()`:
```swift
        let format = engine.outputNode.inputFormat(forBus: 0)
        engine.connect(sourceNode, to: eq, format: format)
        engine.connect(eq, to: engine.mainMixerNode, format: format)
```
with:
```swift
        engine.connect(sourceNode, to: eq, format: outputFormat)
        engine.connect(eq, to: engine.mainMixerNode, format: outputFormat)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -workspace Sculptor.xcworkspace -scheme AudioEngine -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:AudioEngineTests/NoiseEngineFormatTests`
Expected: PASS.

- [ ] **Step 5: Run the full AudioEngine suite** (the graph change could regress existing engine tests)

Run: `xcodebuild test -workspace Sculptor.xcworkspace -scheme AudioEngine -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add AudioEngine/Sources/NoiseEngine.swift AudioEngine/Tests/NoiseEngineFormatTests.swift
git commit -m "fix: build audio graph from explicit format, not output node"
```

---

### Task 8: Interruption + route-change handling

**Files:**
- Create: `AudioEngine/Sources/AudioSessionPolicy.swift`
- Modify: `AudioEngine/Sources/NoiseEngine.swift`
- Create: `AudioEngine/Tests/AudioSessionPolicyTests.swift`

**Interfaces:**
- Produces:
  - `enum InterruptionAction { case pause, resume, none }`
  - `func interruptionAction(type:AVAudioSession.InterruptionType, options:AVAudioSession.InterruptionOptions, wasPlaying:Bool) -> InterruptionAction`
  - `enum RouteAction { case pause, none }`
  - `func routeChangeAction(reason:AVAudioSession.RouteChangeReason) -> RouteAction`
  - `NoiseEngine.isPlaying: Bool` (`private(set)`); `NoiseEngine.onPlaybackStateChange: ((Bool) -> Void)?` — fired on main when playback state changes (incl. interruption-driven).

- [ ] **Step 1: Write the failing tests**

`AudioEngine/Tests/AudioSessionPolicyTests.swift`:
```swift
import Testing
import AVFoundation
@testable import AudioEngine

@Test func interruptionBeganPauses() {
    #expect(interruptionAction(type: .began, options: [], wasPlaying: true) == .pause)
}

@Test func interruptionEndedResumesOnlyIfWasPlayingAndShouldResume() {
    #expect(interruptionAction(type: .ended, options: .shouldResume, wasPlaying: true) == .resume)
    #expect(interruptionAction(type: .ended, options: .shouldResume, wasPlaying: false) == .none)
    #expect(interruptionAction(type: .ended, options: [], wasPlaying: true) == .none)
}

@Test func routeChangePausesOnlyWhenOldDeviceGone() {
    #expect(routeChangeAction(reason: .oldDeviceUnavailable) == .pause)
    #expect(routeChangeAction(reason: .newDeviceAvailable) == .none)
    #expect(routeChangeAction(reason: .categoryChange) == .none)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -workspace Sculptor.xcworkspace -scheme AudioEngine -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:AudioEngineTests/AudioSessionPolicyTests`
Expected: FAIL — symbols not defined.

- [ ] **Step 3: Implement `AudioSessionPolicy.swift`**

```swift
import AVFoundation

public enum InterruptionAction: Equatable { case pause, resume, none }

/// Pure decision for an AVAudioSession interruption notification.
public func interruptionAction(
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

public enum RouteAction: Equatable { case pause, none }

/// Pure decision for an AVAudioSession route-change notification.
public func routeChangeAction(reason: AVAudioSession.RouteChangeReason) -> RouteAction {
    reason == .oldDeviceUnavailable ? .pause : .none
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -workspace Sculptor.xcworkspace -scheme AudioEngine -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:AudioEngineTests/AudioSessionPolicyTests`
Expected: PASS.

- [ ] **Step 5: Wire the observers into `NoiseEngine.swift`**

Add stored state after `outputFormat`:
```swift
    /// Whether the engine is currently producing audio. Driven by start/stop
    /// and by interruption/route handling. Observed by the UI.
    public private(set) var isPlaying = false {
        didSet { if oldValue != isPlaying { onPlaybackStateChange?(isPlaying) } }
    }
    /// Fired on the main queue whenever `isPlaying` changes.
    public var onPlaybackStateChange: ((Bool) -> Void)?
```

At the end of `init()` (after the `connect` calls), register observers:
```swift
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(handleInterruption(_:)),
                       name: AVAudioSession.interruptionNotification, object: nil)
        nc.addObserver(self, selector: #selector(handleRouteChange(_:)),
                       name: AVAudioSession.routeChangeNotification, object: nil)
```

In `deinit`, add as the first line:
```swift
        NotificationCenter.default.removeObserver(self)
```

Replace `start()` and `stop()` so they own `isPlaying`:
```swift
    public func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        if !engine.isRunning { try engine.start() }
        isPlaying = true
    }

    public func stop() {
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
        isPlaying = false
    }
```

Add the notification handlers before the closing brace of the class:
```swift
    @objc private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        let opts = (info[AVAudioSessionInterruptionOptionKey] as? UInt)
            .map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
        switch interruptionAction(type: type, options: opts, wasPlaying: isPlaying) {
        case .pause:  stop()
        case .resume: try? start()
        case .none:   break
        }
    }

    @objc private func handleRouteChange(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        if routeChangeAction(reason: reason) == .pause { stop() }
    }
```

- [ ] **Step 6: Run the full AudioEngine suite**

Run: `xcodebuild test -workspace Sculptor.xcworkspace -scheme AudioEngine -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: all pass, output pristine.

- [ ] **Step 7: Commit**

```bash
git add AudioEngine/Sources/AudioSessionPolicy.swift AudioEngine/Sources/NoiseEngine.swift AudioEngine/Tests/AudioSessionPolicyTests.swift
git commit -m "feat: handle audio interruptions and route changes"
```

---

### Task 9: SculptViewModel (replace SpikeViewModel)

**Files:**
- Create: `Sculptor/Sources/SculptViewModel.swift`
- Create: `Sculptor/Tests/SculptViewModelTests.swift`
- Modify: `Project.swift` (add a `SculptorTests` unit-test target)

Note: `SpikeViewModel.swift` and `RootView.swift` stay in place this task so the
app target keeps compiling (the test host must build). Both are deleted in Task 10
when `SculptView` replaces them.

**Interfaces:**
- Consumes: `NoiseEngine`, `NoisePreset`.
- Produces: `SculptViewModel` (`@MainActor`, `ObservableObject`): `@Published gains:[Float]`, `@Published private(set) isPlaying:Bool`, `@Published private(set) selectedPreset:NoisePreset?`, `@Published errorText:String?`, `let frequencies:[Float]`; methods `togglePlay()`, `setGain(band:Int, dB:Float)`, `select(_:NoisePreset)`.

- [ ] **Step 1: Add a `SculptorTests` target to `Project.swift`**

After the `Sculptor` app target, add:
```swift
        ,
        .target(
            name: "SculptorTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.sculptor.app.tests",
            deploymentTargets: .iOS("17.0"),
            sources: ["Sculptor/Tests/**"],
            dependencies: [.target(name: "Sculptor")]
        )
```
(Place the comma correctly so the array stays valid.)

- [ ] **Step 2: Write the failing tests**

`Sculptor/Tests/SculptViewModelTests.swift`:
```swift
import Testing
@testable import Sculptor
import AudioEngine

@MainActor
@Test func selectPresetUpdatesGainsAndSelection() {
    let vm = SculptViewModel()
    vm.select(.pink)
    #expect(vm.gains == NoisePreset.pink.gains)
    #expect(vm.selectedPreset == .pink)
}

@MainActor
@Test func draggingABandClearsSelectedPreset() {
    let vm = SculptViewModel()
    vm.select(.pink)
    vm.setGain(band: 0, dB: 5)
    #expect(vm.selectedPreset == nil)
    #expect(vm.gains[0] == 5)
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `tuist generate --no-open && xcodebuild test -workspace Sculptor.xcworkspace -scheme Sculptor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SculptorTests`
Expected: FAIL — `SculptViewModel` not found.

- [ ] **Step 4: Create `SculptViewModel.swift`**

```swift
import SwiftUI
import AudioEngine

@MainActor
final class SculptViewModel: ObservableObject {
    @Published var gains: [Float]
    @Published private(set) var isPlaying = false
    @Published private(set) var selectedPreset: NoisePreset?
    @Published var errorText: String?

    let frequencies: [Float] = [60, 125, 250, 500, 1000, 2000, 4000, 8000]
    private let engine: NoiseEngine

    init(engine: NoiseEngine = NoiseEngine()) {
        self.engine = engine
        gains = [Float](repeating: 0, count: 8)
        engine.onPlaybackStateChange = { [weak self] playing in
            Task { @MainActor in self?.isPlaying = playing }
        }
    }

    func togglePlay() {
        if isPlaying {
            engine.stop()
        } else {
            do { try engine.start() }
            catch { errorText = error.localizedDescription }
        }
        isPlaying = engine.isPlaying
    }

    func setGain(band: Int, dB: Float) {
        gains[band] = dB
        engine.setGain(band: band, dB: dB)
        selectedPreset = nil
    }

    func select(_ preset: NoisePreset) {
        engine.apply(preset)
        gains = preset.gains
        selectedPreset = preset
    }
}
```

(`SpikeViewModel.swift` stays in place — deleted in Task 10. The app target must
keep compiling because it hosts `SculptorTests`.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -workspace Sculptor.xcworkspace -scheme Sculptor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SculptorTests`
Expected: PASS (2 tests). The app target still compiles (`RootView`/`SpikeViewModel` untouched).

- [ ] **Step 6: Commit**

```bash
git add Project.swift Sculptor/Sources/SculptViewModel.swift Sculptor/Tests/SculptViewModelTests.swift
git commit -m "feat: add SculptViewModel"
```

---

### Task 10: SculptView + app wiring + smoke test

**Files:**
- Create: `Sculptor/Sources/SculptView.swift`
- Delete: `Sculptor/Sources/RootView.swift`
- Delete: `Sculptor/Sources/SpikeViewModel.swift`
- Modify: `Sculptor/Sources/SculptorApp.swift`

**Interfaces:**
- Consumes: `SculptViewModel`, `DesignSystem` (`BandSlider`, `PresetChip`, `DockCard`, `DockButton`, `DockColor`, `DockType`, `DockSpacing`), `NoisePreset`.

- [ ] **Step 1: Create `SculptView.swift`**

```swift
import SwiftUI
import AudioEngine
import DesignSystem

struct SculptView: View {
    @StateObject private var vm = SculptViewModel()

    private let presets: [(NoisePreset, String)] = [
        (.white, "White"), (.pink, "Pink"), (.brown, "Brown"),
        (.grey, "Grey"), (.speechBlocker, "Speech blocker")
    ]

    var body: some View {
        ZStack {
            DockColor.background.ignoresSafeArea()

            VStack(spacing: DockSpacing.xl) {
                Text("Sculpt")
                    .font(DockType.font(24, .semibold))
                    .foregroundStyle(DockColor.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                DockCard {
                    HStack(alignment: .bottom, spacing: DockSpacing.xs) {
                        ForEach(0..<8, id: \.self) { i in
                            VStack(spacing: DockSpacing.sm) {
                                BandSlider(
                                    value: Binding(
                                        get: { vm.gains[i] },
                                        set: { vm.setGain(band: i, dB: $0) }
                                    ),
                                    range: -24...12
                                )
                                .frame(maxWidth: .infinity)
                                .frame(height: 200)
                                Text(label(vm.frequencies[i]))
                                    .font(DockType.font(10, .medium))
                                    .foregroundStyle(DockColor.textTertiary)
                                    .fixedSize()
                            }
                        }
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DockSpacing.sm) {
                        ForEach(presets, id: \.0) { preset, title in
                            PresetChip(title: title, isSelected: vm.selectedPreset == preset) {
                                vm.select(preset)
                            }
                        }
                    }
                }

                DockButton(title: vm.isPlaying ? "Pause" : "Play") { vm.togglePlay() }

                if let err = vm.errorText {
                    Text(err).font(DockType.font(12)).foregroundStyle(.red)
                }

                Spacer()
            }
            .padding(DockSpacing.xl)
        }
    }

    private func label(_ f: Float) -> String {
        f >= 1000 ? "\(Int(f / 1000))k" : "\(Int(f))"
    }
}

#Preview { SculptView() }
```

- [ ] **Step 2: Update `SculptorApp.swift`** to root `SculptView`

Replace the body's `RootView()` with `SculptView()`. The file should read:
```swift
import SwiftUI

@main
struct SculptorApp: App {
    var body: some Scene {
        WindowGroup {
            SculptView()
        }
    }
}
```

- [ ] **Step 3: Delete the old spike files**

Run: `git rm Sculptor/Sources/RootView.swift Sculptor/Sources/SpikeViewModel.swift`

- [ ] **Step 4: Build, run, and screenshot the app**

Run: `tuist generate --no-open` then build+run on the simulator (XcodeBuildMCP `build_run_sim`, defaults: workspace `Sculptor.xcworkspace`, scheme `Sculptor`, sim `iPhone 17 Pro`), then capture a screenshot.
Expected: build succeeds, app launches without crash, screenshot shows: dark background, "Sculpt" title, a card with 8 vertical teal sliders + freq labels (60→8k), the 5-chip preset row, and a teal Play button. Tapping a chip moves the sliders; Play toggles to Pause.

- [ ] **Step 5: Run the full test suite across all schemes**

Run:
```bash
xcodebuild test -workspace Sculptor.xcworkspace -scheme AudioEngine -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild test -workspace Sculptor.xcworkspace -scheme DesignSystem -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild test -workspace Sculptor.xcworkspace -scheme Sculptor -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```
Expected: all green, output pristine.

- [ ] **Step 6: Commit**

```bash
git add Sculptor/Sources/SculptView.swift Sculptor/Sources/SculptorApp.swift
git commit -m "feat: designed Sculpt screen wired to NoiseEngine"
```

---

## Self-Review

**Spec coverage:**
- DesignSystem framework + modular architecture → Tasks 1–5. ✅
- Dock tokens (color/type/spacing/radius) → Tasks 2, 3. ✅
- Lexend fonts bundled + registered → Task 3. ✅
- Components (BandSlider, PresetChip, DockCard, DockButton) → Tasks 4, 5. ✅
- Sculpt screen + VM, 5 preset chips, temporary transport, chip↔custom interaction → Tasks 9, 10. ✅
- Explicit AVAudioFormat → Task 7. ✅
- Interruption + route handling → Task 8. ✅
- Grey + Speech-blocker presets → Task 6. ✅
- Phase-0 spike UI removed → Tasks 9, 10. ✅
- Testing across all units → every task has tests except the pure-view components (Task 5), explicitly justified and covered by the Task 10 smoke test. ✅

**Placeholder scan:** No TBD/TODO; all code shown in full; gain tables are concrete starter values (deferred *tuning* is a stated decision, not a placeholder). ✅

**Type consistency:** `onPlaybackStateChange`/`isPlaying` defined in Task 8 and consumed in Task 9; `NoisePreset.grey/.speechBlocker` defined in Task 6 and consumed in Tasks 9–10; `bandSliderFillFraction`, `DockColor.*`, `DockType.font`, `DockSpacing.*` defined in Tasks 2–4 and consumed in Tasks 5, 10. Names match across tasks. ✅
