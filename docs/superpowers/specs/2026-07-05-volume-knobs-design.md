# Volume Knobs — DJ-style circular volume controls

**Date:** 2026-07-05
**Status:** Approved (user confirmed via visual companion iteration v5)

## Summary

Replace both Home volume rows (app-gain `Slider` + `SystemVolumeSlider` MPVolumeView bar) with two circular glow-ring knobs side by side: **NOISE** (app gain) and **PHONE** (system volume). Style locked through mockup iteration: open glow ring, no physical knob disc, SF Symbol icon at rest, bare number while dragging.

## Visual (locked)

- 270° sweep, gap centered at bottom (start ≈ 7:30, end ≈ 4:30 clock positions).
- Dark track ring; teal (`DockColor.accent`) progress arc with soft glow; bright dot at arc tip.
- Center content: SF Symbol icon when idle (`speaker.wave.2.fill` for NOISE, `iphone` for PHONE); while finger is down, icon is replaced by the bare integer `0–100` (no `%` sign). Icon returns on release.
- Label below knob: `NOISE` / `PHONE`, small uppercase, letter-spaced, `DockColor.textTertiary`.
- No emoji anywhere — SF Symbols only.

## Components

### `VolumeKnob` (DesignSystem)

Reusable SwiftUI view. Pure UI; no audio/session knowledge.

- API: `VolumeKnob(value: Binding<Float>, icon: String, label: String)` — value 0…1.
- Drawing: `Circle().trim(from:to:)` for track and progress + `shadow` glow + tip dot; rotated so the gap sits at bottom.
- Gesture: circular drag only. `DragGesture(minimumDistance: 0)`; angle of touch point around center via `atan2`; mapped to sweep fraction; clamped at both ends — crossing the bottom gap never wraps 100→0 or 0→100 (gesture latches to the previous value on any >0.5 single-frame jump; tracking resumes once the finger returns near it).
- `isDragging` internal state controls icon/number swap.
- Haptics: light impact when value hits 0.0 or 1.0 during a drag.
- Geometry math lives in pure static functions (e.g. `KnobGeometry.value(forAngle:)`, `angle(forValue:)`, `trimFraction(forValue:)`) — unit-testable without views.

### `SystemVolume` (Sculptor)

Replaces `SystemVolumeSlider.swift`.

- **Read:** `AVAudioSession.sharedInstance().outputVolume` observed via KVO → published value; PHONE knob tracks hardware buttons live.
- **Write:** hidden `MPVolumeView` (alpha 0, ~1pt, kept in the view hierarchy), locate its `UISlider` subview, set `.value`. Known, widely-used trick; accepted trade-offs: iOS volume HUD may appear while turning; an iOS update could break setting, in which case the knob degrades to display-only.
- Requires audio session active for reliable `outputVolume` (already the case while playing; observe lifecycle-safely otherwise).

## Home layout

Remove both existing volume rows. Insert one `HStack`: NOISE knob bound to `vm.masterVolume` (existing persistence and engine plumbing untouched) and PHONE knob bound through `SystemVolume`. Positioned where the old rows were (between ScopeVisualizer and status text).

## Testing

- Unit (DesignSystem): `KnobGeometry` pure functions — value↔angle at 0 / 0.5 / 1.0, clamping in the bottom gap, trim fraction.
- Existing `SystemVolumeSliderTests` removed with the component it tested.
- VM tests unchanged (masterVolume already covered).
- Device-only checks: PHONE knob follows hardware buttons; turning PHONE knob changes system volume; HUD behavior.

## Out of scope

- Vertical-drag gesture (explicitly rejected — circular only).
- Percent readout at rest, `%` symbol anywhere.
- Knob for anything other than these two volumes.
