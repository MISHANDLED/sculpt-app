# Phase 2C — Sleep Timer (Moon Button Auto-Stop)

**Date:** 2026-06-28
**Status:** Approved (design), ready for implementation planning
**Predecessors:** Phase 2A (IA restructure — moon button placeholder), Phase 2B (preset management).

## Context

Phase 2A added a non-functional moon button to the home top bar (`onOpenTimer: {}` placeholder). This phase makes it a sleep timer: tap the moon to pick a duration; when it elapses, playback auto-stops. The button shows a live `MM:SS` countdown while armed.

The auto-stop reuses the existing `engine.stop()` path (via a small `stopPlayback()` refactor in `PlaybackViewModel`) — no AudioEngine changes. All timer state lives on `PlaybackViewModel`; the moon `Menu` calls the VM directly, so the `onOpenTimer` closure is removed (consistent with the project's VM-over-closures rule).

## Goals

1. Tap the moon → a `Menu` to pick Off / 15 / 30 / 45 / 60 minutes.
2. Arm a wall-clock deadline; auto-stop playback when it elapses.
3. Show a live `MM:SS` countdown on the moon button while armed; plain moon when off.
4. Cancel the timer on manual stop (the user pausing makes the timer moot).

## Non-Goals (Phase 2C)

- Custom/arbitrary durations (fixed set only).
- Fade-out before stop, "shake to extend", notifications.
- Playback-linked countdown (semantics are wall-clock; pausing does NOT pause the countdown — manual pause cancels it).
- Persisting an armed timer across app relaunch.
- Stereo width, gentle drift, Dynamic Type, light theme, iCloud sync (still deferred).

## Architecture

```
PlaybackViewModel (@MainActor, ObservableObject)
  @Published private(set) var sleepMinutes: Int?         // armed duration (nil = off) — menu checkmark
  @Published private(set) var sleepRemaining: TimeInterval?  // live countdown (nil = off) — moon label
  private var sleepDeadline: Date?                        // now + minutes*60
  private var sleepTask: Task<Void, Never>?              // 1 Hz tick loop

  func startSleepTimer(minutes: Int)
  func cancelSleepTimer()
  func _sleepTick(now: Date = Date())                    // test seam, like _ingestScopeSamples
  private func stopPlayback()                             // shared engine-stop path

HomeView
  moon Menu { Off / 15 / 30 / 45 / 60 } → vm.startSleepTimer(minutes:) / vm.cancelSleepTimer()
  moon label: armed → moon.fill + accent + formatCountdown(remaining); off → plain moon (36×36)

RootView
  HomeView(...) — drops the onOpenTimer argument
```

- One shared `PlaybackViewModel` (`@StateObject` in `RootView`, `@ObservedObject` in `HomeView`).
- Timer state is VM-owned `@Published`; the menu actions call the VM (no closures threaded through `RootView`).

## Component 1 — formatCountdown helper

New file `Sculptor/Sources/SleepFormatting.swift` — a pure, testable free function:

```swift
/// Zero-padded MM:SS for a countdown. Negative input clamps to "00:00".
func formatCountdown(_ seconds: Int) -> String {
    let s = max(0, seconds)
    return String(format: "%02d:%02d", s / 60, s % 60)
}
```

**Tests** (`Sculptor/Tests/SleepFormattingTests.swift`): `0 → "00:00"`, `65 → "01:05"`, `900 → "15:00"`, `3600 → "60:00"`, `-5 → "00:00"`.

## Component 2 — PlaybackViewModel sleep timer

New state:

```swift
@Published private(set) var sleepMinutes: Int?
@Published private(set) var sleepRemaining: TimeInterval?
private var sleepDeadline: Date?
private var sleepTask: Task<Void, Never>?
```

Refactor stop into a shared path and cancel the timer on manual stop:

```swift
private func stopPlayback() {
    engine.stop()
    scopeSamples = []
    isPlaying = engine.isPlaying
}

func togglePlay() {
    if isPlaying {
        stopPlayback()
        cancelSleepTimer()          // manual stop cancels the timer
    } else {
        do { try engine.start() }
        catch { errorText = error.localizedDescription }
        isPlaying = engine.isPlaying
    }
}
```

Timer control:

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

Notes:
- `_sleepTick` runs on the `@MainActor` VM (the loop is created in a `@MainActor` context, so the `Task` inherits the actor).
- Starting a timer while one is armed replaces it (cancels the prior task first).
- Expiry and manual stop both end in `stopPlayback()` + `cancelSleepTimer()`; `engine.stop()` is idempotent.

**Tests** (`Sculptor/Tests/PlaybackViewModelTests.swift`):
- `startSleepTimer(minutes: 30)` → `sleepMinutes == 30`, `sleepRemaining` within `(30*60 − 1 … 30*60]`.
- `cancelSleepTimer()` after start → `sleepMinutes == nil`, `sleepRemaining == nil`.
- `_sleepTick(now:)` with a future `now` past the deadline → `sleepRemaining == nil`, `sleepMinutes == nil` (expired + cleared).
- `_sleepTick(now:)` with `now` before the deadline → `sleepRemaining` ≈ `deadline − now`, `sleepMinutes` unchanged.
- `startSleepTimer` twice → second call's `sleepMinutes` wins (replaced).

## Component 3 — HomeView moon Menu + countdown label

Replace the moon `Button` with a `Menu`:

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

`moonLabel` (computed):
- **Armed** (`vm.sleepRemaining != nil`): a capsule — `moon.fill` + `formatCountdown(Int(remaining))` — accent foreground, `surface2` background, `border` stroke.
- **Off**: the existing 36×36 circle with a plain `moon`, `textPrimary`, `surface2`, `border`.

The live `MM:SS` updates because `vm.sleepRemaining` is `@Published` and ticked each second.

(Presentational; verified via build + screenshots.)

## Component 4 — RootView

Remove the `onOpenTimer: {}` argument from the `HomeView(...)` call; remove the `onOpenTimer` parameter from `HomeView`'s definition (Component 3).

## Data Flow

```
moon menu pick (N min) → vm.startSleepTimer(N) → deadline = now+N*60, sleepRemaining set, tick loop starts
tick (1 Hz)            → vm._sleepTick() → remaining>0: update sleepRemaining (moon MM:SS refreshes)
                                          remaining≤0: stopPlayback() + cancelSleepTimer() (audio stops, moon → plain)
moon menu "Off"        → vm.cancelSleepTimer() → state cleared, moon → plain
manual pause/stop      → vm.togglePlay() stop branch → stopPlayback() + cancelSleepTimer()
```

## Error Handling

- `engine.stop()` is idempotent; calling it at expiry when already stopped is safe.
- Replacing an armed timer cancels the prior `Task` before launching a new one (no leaked loops).
- `formatCountdown` clamps negatives to `"00:00"` (guards a tick that races slightly past zero).
- Interruptions/route changes stop audio via the engine's own handlers; they do not cancel the sleep timer (only a *manual* `togglePlay` stop does). The next tick after audio already stopped still expires/clears normally.

## Testing

- **formatCountdown:** the cases listed in Component 1.
- **PlaybackViewModel:** the cases listed in Component 2 (start/cancel/replace + `_sleepTick` expiry and non-expiry via injected `now`). No real-time waits.
- **Moon UI:** build + launch + screenshots of (a) the moon menu open with durations, (b) the armed moon showing a live `MM:SS`. (No UI-tap tool: best-effort screenshots; rely on build + unit tests + code review.)
- Swift Testing, pristine output.

## Global Constraints (carried)

- iOS 17.0 floor; Tuist-only generation (no committed `.xcodeproj`/`.xcworkspace`).
- Band frequencies 60/125/250/500/1000/2000/4000/8000 Hz; gain range −24…+12 dB.
- RT-safe render callback untouched (this phase adds no engine code).
- Bundle id prefix `com.sculptor`. Dark theme only.
- Font PostScript names `Dock-Lexend-*` via `DockType.font`.
- ONE `PlaybackViewModel` as `@StateObject` in `RootView`, `@ObservedObject` elsewhere.
- Cross-view coordination via `@Published` VM state, not callback closures.
- Swift Testing, pristine output.

## Open Items (deferred)

- Persisting an armed timer across relaunch; fade-out before stop; custom durations.
- Stereo width, gentle drift, Dynamic Type, light theme, iCloud sync.
