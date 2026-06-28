# Phase 2C — Sleep Timer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the home moon button a sleep timer: pick a duration from a menu, auto-stop playback at a wall-clock deadline, and show a live MM:SS countdown while armed.

**Architecture:** All timer state lives on `PlaybackViewModel` (`sleepMinutes`, `sleepRemaining`, private deadline + tick `Task`). A pure `formatCountdown` helper renders MM:SS. The home moon becomes a `Menu` calling the VM directly; the `onOpenTimer` closure is removed. Auto-stop reuses the existing `engine.stop()` path via a `stopPlayback()` refactor — no AudioEngine changes.

**Tech Stack:** SwiftUI (iOS 17+), Swift Concurrency (`Task`/`Task.sleep`), AudioEngine + DesignSystem modules, Swift Testing, Tuist.

## Global Constraints

- iOS 17.0 floor; Tuist-only generation — run `tuist generate` before any build; no committed `.xcodeproj`/`.xcworkspace`.
- Band frequencies `[60, 125, 250, 500, 1000, 2000, 4000, 8000]` Hz; gain range `−24…+12 dB`.
- RT-safe render callback in `NoiseEngine` must not be touched; this phase adds NO engine code.
- Bundle id prefix `com.sculptor`. Dark theme only.
- Font via `DockType.font(_:_:)`; colors via `DockColor.*`; spacing via `DockSpacing.*`.
- ONE `PlaybackViewModel` as `@StateObject` in `RootView`, `@ObservedObject` elsewhere.
- Cross-view coordination via `@Published` VM state, not callback closures.
- Swift Testing (`@Suite`, `@Test`, `#expect`) — pristine output, zero warnings.
- Test scheme: `Sculptor`. Session default sim: "iPhone 17 Pro".
- Commit prefix: `feat:` new code, `refactor:` refactors, `test:` test-only.

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| **Create** | `Sculptor/Sources/SleepFormatting.swift` | `formatCountdown(_:)` pure MM:SS helper |
| **Create** | `Sculptor/Tests/SleepFormattingTests.swift` | Tests for `formatCountdown` |
| Modify | `Sculptor/Sources/PlaybackViewModel.swift` | Sleep state, start/cancel/_sleepTick, stopPlayback refactor, togglePlay cancel |
| Modify | `Sculptor/Tests/PlaybackViewModelTests.swift` | Tests for sleep-timer state machine |
| Modify | `Sculptor/Sources/HomeView.swift` | Moon `Menu` + countdown label; drop `onOpenTimer` param |
| Modify | `Sculptor/Sources/RootView.swift` | Drop the `onOpenTimer:` argument |

---

### Task 1: formatCountdown helper

**Files:**
- Create: `Sculptor/Sources/SleepFormatting.swift`
- Create: `Sculptor/Tests/SleepFormattingTests.swift`

**Interfaces:**
- Produces: `func formatCountdown(_ seconds: Int) -> String` — zero-padded `MM:SS`, negatives clamp to `"00:00"`.

- [ ] **Step 1: Write the failing tests**

Create `Sculptor/Tests/SleepFormattingTests.swift`:

```swift
import Testing
@testable import Sculptor

@Suite struct SleepFormattingTests {
    @Test func zeroIsDoubleZero() {
        #expect(formatCountdown(0) == "00:00")
    }

    @Test func underOneMinutePadsSeconds() {
        #expect(formatCountdown(65) == "01:05")
    }

    @Test func fifteenMinutes() {
        #expect(formatCountdown(900) == "15:00")
    }

    @Test func sixtyMinutes() {
        #expect(formatCountdown(3600) == "60:00")
    }

    @Test func negativeClampsToZero() {
        #expect(formatCountdown(-5) == "00:00")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/devansh.mohata@zomato.com/Documents/Random/Noise && tuist generate && xcodebuild test -scheme Sculptor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "formatCountdown|cannot find|error:|Build FAILED"`
Expected: compile error — `cannot find 'formatCountdown' in scope`.

- [ ] **Step 3: Create the helper**

Create `Sculptor/Sources/SleepFormatting.swift`:

```swift
import Foundation

/// Zero-padded MM:SS for a countdown. Negative input clamps to "00:00".
func formatCountdown(_ seconds: Int) -> String {
    let s = max(0, seconds)
    return String(format: "%02d:%02d", s / 60, s % 60)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Sculptor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "Test Suite.*passed|failed|error:"`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sculptor/Sources/SleepFormatting.swift Sculptor/Tests/SleepFormattingTests.swift
git commit -m "feat: formatCountdown MM:SS helper

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 2: PlaybackViewModel sleep timer

**Files:**
- Modify: `Sculptor/Sources/PlaybackViewModel.swift`
- Modify: `Sculptor/Tests/PlaybackViewModelTests.swift`

**Interfaces:**
- Produces: `@Published private(set) var sleepMinutes: Int?`; `@Published private(set) var sleepRemaining: TimeInterval?`; `func startSleepTimer(minutes: Int)`; `func cancelSleepTimer()`; `func _sleepTick(now: Date = Date())`.
- Consumes: existing `engine.stop()`, `scopeSamples`, `isPlaying`.

- [ ] **Step 1: Write the failing tests**

Add these tests inside the `PlaybackViewModelTests` suite in `Sculptor/Tests/PlaybackViewModelTests.swift` (after the existing `presetToRenameSetAndClear` test). Note `import Foundation` is already present in that file.

```swift
    @Test func startSleepTimerSetsMinutesAndRemaining() {
        let vm = PlaybackViewModel()
        vm.startSleepTimer(minutes: 30)
        #expect(vm.sleepMinutes == 30)
        let remaining = vm.sleepRemaining ?? 0
        #expect(remaining > 30 * 60 - 1 && remaining <= 30 * 60)
        vm.cancelSleepTimer()   // stop the tick loop
    }

    @Test func cancelSleepTimerClearsState() {
        let vm = PlaybackViewModel()
        vm.startSleepTimer(minutes: 15)
        vm.cancelSleepTimer()
        #expect(vm.sleepMinutes == nil)
        #expect(vm.sleepRemaining == nil)
    }

    @Test func sleepTickBeforeDeadlineUpdatesRemaining() {
        let vm = PlaybackViewModel()
        vm.startSleepTimer(minutes: 30)
        vm._sleepTick(now: Date().addingTimeInterval(60))  // 1 minute elapsed
        let remaining = vm.sleepRemaining ?? 0
        #expect(remaining > 28 * 60 && remaining < 30 * 60)
        #expect(vm.sleepMinutes == 30)
        vm.cancelSleepTimer()
    }

    @Test func sleepTickPastDeadlineStopsAndClears() {
        let vm = PlaybackViewModel()
        vm.startSleepTimer(minutes: 30)
        vm._sleepTick(now: Date().addingTimeInterval(31 * 60))  // past deadline
        #expect(vm.sleepRemaining == nil)
        #expect(vm.sleepMinutes == nil)
        #expect(vm.isPlaying == false)
    }

    @Test func startSleepTimerTwiceReplacesDuration() {
        let vm = PlaybackViewModel()
        vm.startSleepTimer(minutes: 15)
        vm.startSleepTimer(minutes: 45)
        #expect(vm.sleepMinutes == 45)
        vm.cancelSleepTimer()
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Sculptor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "sleepMinutes|startSleepTimer|error:|Build FAILED"`
Expected: compile errors — `value of type 'PlaybackViewModel' has no member 'startSleepTimer'` / `sleepMinutes` / `sleepRemaining` / `_sleepTick`.

- [ ] **Step 3: Add sleep state and refactor stop**

In `Sculptor/Sources/PlaybackViewModel.swift`:

(a) Add these published properties after the existing `presetToRename` line:

```swift
    @Published private(set) var sleepMinutes: Int?
    @Published private(set) var sleepRemaining: TimeInterval?
```

(b) Add these private stored properties after `private let engine: NoiseEngine`:

```swift
    private var sleepDeadline: Date?
    private var sleepTask: Task<Void, Never>?
```

(c) Replace the existing `togglePlay()` with a version that uses a shared `stopPlayback()` and cancels the timer on manual stop:

```swift
    func togglePlay() {
        if isPlaying {
            stopPlayback()
            cancelSleepTimer()
        } else {
            do { try engine.start() }
            catch { errorText = error.localizedDescription }
            isPlaying = engine.isPlaying
        }
    }

    private func stopPlayback() {
        engine.stop()
        scopeSamples = []
        isPlaying = engine.isPlaying
    }
```

(d) Add the timer control methods (place them after `reset()`):

```swift
    func startSleepTimer(minutes: Int) {
        sleepTask?.cancel()
        sleepMinutes = minutes
        sleepDeadline = Date().addingTimeInterval(TimeInterval(minutes * 60))
        sleepRemaining = TimeInterval(minutes * 60)
        sleepTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { break }
                self?._sleepTick()
            }
        }
    }

    func cancelSleepTimer() {
        sleepTask?.cancel()
        sleepTask = nil
        sleepDeadline = nil
        sleepMinutes = nil
        sleepRemaining = nil
    }

    /// One countdown step. Test seam: pass an explicit `now`.
    func _sleepTick(now: Date = Date()) {
        guard let deadline = sleepDeadline else { return }
        let remaining = deadline.timeIntervalSince(now)
        if remaining <= 0 {
            stopPlayback()
            cancelSleepTimer()
        } else {
            sleepRemaining = remaining
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Sculptor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "Test Suite.*passed|failed|error:"`
Expected: all tests pass (existing + 5 new sleep tests).

- [ ] **Step 5: Commit**

```bash
git add Sculptor/Sources/PlaybackViewModel.swift Sculptor/Tests/PlaybackViewModelTests.swift
git commit -m "feat: PlaybackViewModel sleep timer — start/cancel/tick, stopPlayback refactor

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 3: HomeView moon Menu + countdown; RootView drop onOpenTimer

**Files:**
- Modify: `Sculptor/Sources/HomeView.swift`
- Modify: `Sculptor/Sources/RootView.swift`

**Interfaces:**
- Consumes: `vm.sleepMinutes`, `vm.sleepRemaining` (Task 2); `vm.startSleepTimer(minutes:)`, `vm.cancelSleepTimer()`; `formatCountdown(_:)` (Task 1).

- [ ] **Step 1: Replace the moon Button with a Menu in HomeView**

In `Sculptor/Sources/HomeView.swift`:

(a) Remove the `onOpenTimer` property. Change the property block from:

```swift
    let onOpenSculpt: () -> Void
    let onOpenPresets: () -> Void
    let onOpenTimer: () -> Void
```

to:

```swift
    let onOpenSculpt: () -> Void
    let onOpenPresets: () -> Void
```

(b) Replace the moon `Button { ... }` (the second button in the top-bar trailing `HStack`) with this `Menu`:

```swift
                Menu {
                    Button { vm.cancelSleepTimer() } label: {
                        Label("Off", systemImage: vm.sleepMinutes == nil ? "checkmark" : "")
                    }
                    ForEach([15, 30, 45, 60], id: \.self) { mins in
                        Button { vm.startSleepTimer(minutes: mins) } label: {
                            Label("\(mins) minutes", systemImage: vm.sleepMinutes == mins ? "checkmark" : "")
                        }
                    }
                } label: {
                    moonLabel
                }
                .buttonStyle(.plain)
```

(c) Add the `moonLabel` computed property in the `// MARK: - Helpers` section (after `presetName`):

```swift
    @ViewBuilder private var moonLabel: some View {
        if let remaining = vm.sleepRemaining {
            HStack(spacing: 4) {
                Image(systemName: "moon.fill")
                Text(formatCountdown(Int(remaining)))
                    .font(DockType.font(13, .medium))
                    .monospacedDigit()
            }
            .font(.system(size: 16))
            .foregroundStyle(DockColor.accent)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(DockColor.surface2)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(DockColor.border, lineWidth: 1))
        } else {
            Image(systemName: "moon")
                .font(.system(size: 16))
                .foregroundStyle(DockColor.textPrimary)
                .frame(width: 36, height: 36)
                .background(DockColor.surface2)
                .clipShape(Circle())
                .overlay(Circle().stroke(DockColor.border, lineWidth: 1))
        }
    }
```

(d) Update the `#Preview` at the bottom of the file — remove the `onOpenTimer:` argument:

```swift
#Preview {
    HomeView(vm: PlaybackViewModel(), onOpenSculpt: {}, onOpenPresets: {})
        .modelContainer(for: CustomPreset.self, inMemory: true)
}
```

- [ ] **Step 2: Drop onOpenTimer in RootView**

In `Sculptor/Sources/RootView.swift`, change the `HomeView(...)` call from:

```swift
        HomeView(
            vm: vm,
            onOpenSculpt: { showSculpt = true },
            onOpenPresets: { showPresets = true },
            onOpenTimer: {}
        )
```

to:

```swift
        HomeView(
            vm: vm,
            onOpenSculpt: { showSculpt = true },
            onOpenPresets: { showPresets = true }
        )
```

- [ ] **Step 3: Build and run full test suite**

Run: `cd /Users/devansh.mohata@zomato.com/Documents/Random/Noise && tuist generate && xcodebuild build -scheme Sculptor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|warning:|Build succeeded|Build FAILED"`
Expected: `Build succeeded`, no errors/warnings.

Then: `xcodebuild test -scheme Sculptor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "Test Suite.*passed|failed|error:"`
Expected: all tests pass.

- [ ] **Step 4: Launch on simulator and verify**

Boot/install/launch via the xcodebuild MCP tools (build_run_sim with session defaults). Verify and screenshot:

1. **Moon menu** — tap the moon button → menu shows Off / 15 / 30 / 45 / 60 minutes.
2. **Armed countdown** — pick a duration → the moon button becomes a capsule with `moon.fill` + a live `MM:SS` that ticks down each second; the menu shows a checkmark on the chosen duration.
3. **Off** — pick Off → the moon reverts to the plain circle.

Take screenshots of states 1 and 2. If a tap cannot be driven via the MCP UI tools, capture what is reachable and note precisely what could/couldn't be verified.

- [ ] **Step 5: Commit**

```bash
git add Sculptor/Sources/HomeView.swift Sculptor/Sources/RootView.swift
git commit -m "feat: home moon sleep-timer menu with live MM:SS countdown

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```
