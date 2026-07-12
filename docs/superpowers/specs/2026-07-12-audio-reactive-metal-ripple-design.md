# Audio-Reactive Metal Living Contours

**Date:** 2026-07-12
**Status:** Approved in discussion; awaiting written-spec review
**Supersedes:** The Home oscilloscope from `2026-06-28-phase1b-nowplaying-visualizer-design.md`

## Summary

Replace Home's oscilloscope with a full-screen, continuously moving **living contour** background. The effect renders as a procedural Metal shader behind all Home content. It drifts gently when playback is paused and responds at a balanced intensity to the spectrum of the actual post-EQ audio while playback is active.

Frequency analysis uses a reusable Accelerate/vDSP FFT on a dedicated analysis queue. Metal is reserved for full-screen per-pixel rendering, where GPU execution provides the greatest benefit. Audio analysis never blocks playback and may drop stale frames under load.

The effect exists only on Home. It continues rendering while Sculpt is presented and remains visible in the uncovered Home area around the sheet; the sheet itself stays opaque. The effect is not added to Presets and stops rendering and analyzing audio when Home is covered by Presets or the app becomes inactive.

## Goals

1. Remove the oscilloscope from Home and replace it with the approved living-contour background.
2. Make contour motion respond to the real post-EQ spectrum, not only to EQ slider values or a simulated envelope.
3. Preserve a calm, low-intensity drift while paused.
4. Use accurate eight-band spectral analysis aligned with Sculptor's EQ centers.
5. Render the effect in one procedural Metal pass without textures, particles, or offscreen blur layers.
6. Preserve real-time audio safety and prevent visual work from affecting playback.
7. Respect scene visibility, Low Power Mode, and Reduce Motion.

## Non-Goals

- Adding the effect to Sculpt or Presets as an independent background.
- Making the ripple interactive with touch, tilt, or device motion.
- Changing the existing noise synthesis, EQ response, presets, or loudness normalization.
- Using the GPU for FFT analysis.
- Adding user-facing visualizer settings, themes, or intensity controls.
- Retaining the oscilloscope as an alternate mode.
- Making PHONE hardware volume alter the generated spectrum.

## Locked Visual Direction

The approved direction is **Living contour, balanced response**.

- Four irregular, nested contour lines occupy the full Home canvas.
- Contours use `DockColor.accent` over the existing near-black background.
- Lines remain translucent enough that labels and controls stay visually dominant.
- Shapes drift, rotate, and deform slowly rather than expanding as perfect circles.
- Playback adds spectrum-driven displacement, edge detail, and glow.
- Pausing removes spectrum-driven energy with a smooth release while preserving gentle ambient movement.
- Peaks produce restrained short accents. The effect must never flash.
- The ripple ignores safe areas, cannot receive touches, and is hidden from accessibility.
- The oscilloscope's former 80-point-high layout region is removed. Existing Home content recenters naturally using the current stack spacing; no replacement spacer is added.

## Architecture

```text
AVAudioEngine EQ output
        │ 4,096 post-EQ mono samples
        ▼
bounded reusable sample mailbox ── keeps only the latest pending frame
        │
        ▼
SpectrumAnalyzer (Accelerate/vDSP analysis queue)
        │ SpectrumSnapshot: 8 bands + RMS + peak
        ▼
PlaybackViewModel (@MainActor)
        │ target spectrum + playback/visibility/master-volume state
        ▼
RippleBackground (SwiftUI TimelineView)
        │ interpolated compact uniforms
        ▼
LivingContours.metal (single full-screen procedural shader)
```

Dependency direction remains unchanged:

- `AudioEngine` owns sample capture and spectrum analysis and has no UI dependency.
- `Sculptor` owns animation policy, Home visibility, and the Metal-backed view.
- `DesignSystem` continues to provide colors, spacing, typography, and foreground controls. It does not gain an `AudioEngine` dependency.

The Metal view and shader stay in the app target. This allows the shader to use the main bundle's default Metal library and keeps spectrum-specific behavior out of the generic DesignSystem package.

## Component 1 — `SpectrumSnapshot` (`AudioEngine`)

Add a public immutable, `Equatable`, `Sendable` value containing:

- `bands: SIMD8<Float>` — normalized energy for the eight EQ-aligned bands.
- `rms: Float` — normalized time-domain RMS.
- `peak: Float` — normalized absolute peak.
- `static let zero` — all values zero.

All published values are finite and clamped to `0...1`. Invalid or non-finite analyzer results are replaced with zero before a snapshot leaves `AudioEngine`.

## Component 2 — `SpectrumAnalyzer` (`AudioEngine`)

`SpectrumAnalyzer` is an internal, stateful analysis object owned by `NoiseEngine`.

### Input handoff

- FFT length is fixed at 4,096 samples. The tap requests 4,096 frames but does not assume AVFAudio will honor that request.
- Allocate one 4,096-float accumulation buffer, two 4,096-float mailbox slots, the Hann window, FFT setup, split-complex storage, magnitudes, and intermediate band storage before tap installation.
- Storage visible to the tap uses fixed raw buffers. The installed block captures a stable unmanaged mailbox context that outlives the tap; it does not capture `NoiseEngine` or create per-callback ownership traffic.
- The tap copies arbitrary channel-0 callback lengths into the accumulation buffer. It publishes only complete 4,096-sample windows; partial windows remain accumulated for the next callback. A callback that completes more than one window is consumed in bounded chunks.
- The two mailbox slots use `Synchronization.Atomic` state transitions (`free → writing → ready → reading → free`) and monotonically increasing sequence numbers. The producer publishes `ready` with release ordering; the worker claims it with acquire ordering before reading sample memory. Returning a slot to `free` and claiming it for writing use the corresponding release/acquire ordering. Publishing uses compare-and-exchange and `memcpy`; it never waits.
- Publishing first tries to claim and overwrite an existing `ready` slot so only the newest pending window survives. If the worker has already claimed that slot, publishing tries the other `free` slot. If neither transition succeeds immediately, the completed window is dropped.
- A serial analysis worker and its 60 Hz polling source are created before tap installation. The tap does not signal a semaphore, enqueue a closure, create a `Task`, or call another wake-up API.
- The worker claims a ready slot atomically, runs the FFT without holding any shared coordination primitive, marks the slot free, and delivers the result asynchronously.
- No FFT, Swift `Array` mutation, heap allocation, lock, semaphore, synchronous dispatch, task creation, ARC ownership change, or blocking wait occurs in the tap callback.

This is a bounded latest-useful-frame policy rather than a queue. Visual freshness matters; processing stale spectrum frames does not. Teardown removes the tap, invalidates the analyzer generation, cancels and joins the polling worker outside the audio callback, and only then destroys the mailbox. The unmanaged callback context therefore remains valid for every possible tap invocation and worker completion.

### FFT and band aggregation

For every accepted buffer:

1. Compute RMS and absolute peak from the unwindowed time-domain samples.
2. Multiply samples by the precomputed Hann window.
3. Run a real-to-complex 4,096-point vDSP FFT using a reused setup.
4. Convert complex output into one-sided power magnitudes, correcting for FFT length and the Hann window's coherent gain before calculating dBFS.
5. Aggregate mean power—not summed power—inside eight frequency ranges. Mean power prevents wider high-frequency ranges from winning only because they contain more FFT bins.
6. Convert each band to dBFS with an epsilon floor, clamp it to `-72...-12 dBFS`, and map that range linearly to `0...1`.
7. Convert RMS with `20 * log10(max(rms, 1e-6))`, clamp it to `-60...-12 dBFS`, and map that range linearly to `0...1`.
8. Convert peak with `20 * log10(max(peak, 1e-6))`, clamp it to `-48...-6 dBFS`, and map that range linearly to `0...1`.

Band centers match the existing EQ:

```text
60, 125, 250, 500, 1,000, 2,000, 4,000, 8,000 Hz
```

Interior boundaries are the geometric mean of adjacent centers. The first band begins at 20 Hz. The final band ends at the lower of 12 kHz and the current Nyquist frequency. The analyzer derives bin ranges from its input sample rate and supports rebuilding those ranges for a new rate.

This feature does not change `NoiseEngine`'s existing 44.1 kHz graph format. Media-services reset recreates the analyzer from the rebuilt graph's format, which remains 44.1 kHz today. Analyzer-level tests also exercise 48 kHz so the component stays correct if the engine format becomes adaptive later.

The analyzer emits raw normalized snapshots. Visual attack/release smoothing belongs to the animation layer so paused decay continues even after the audio tap is removed.

## Component 3 — `NoiseEngine` spectrum tap (`AudioEngine`)

Replace scope-specific API and state with spectrum terminology:

- `onScopeSamples` → `onSpectrumSnapshot`
- `scopeEnabled` → `spectrumAnalysisEnabled`
- `isScopeTapInstalled` → `isSpectrumTapInstalled`
- `_installScopeTap()` → `_installSpectrumTap()`
- `_removeScopeTap()` → `_removeSpectrumTap()`

Behavior:

- Install the tap on the EQ output only when playback and spectrum analysis are both active.
- Remove it when playback stops, analysis is disabled, the app becomes inactive, or the graph is rebuilt.
- Deliver `SpectrumSnapshot` on the main queue.
- After a media-services reset, recreate format-dependent analyzer metadata before reinstalling the tap.
- Analyzer setup or submission failure is non-fatal. Audio playback continues and the UI receives no new target spectrum.

`NoiseEngine` gains an internal analyzer-factory injection seam used by tests. Production uses the real `SpectrumAnalyzer`; tests can inject setup failure, submission failure, or a deterministic fake without changing the public engine API.

All `NoiseEngine` control-plane mutations—start, stop, fade lifecycle, graph rebuild, tap install/remove, analyzer enablement, and generation changes—are main-actor isolated. Interruption, route-change, and media-services notification handlers hop to `@MainActor` before touching the graph, tap, or analyzer lifecycle. The source-node render callback and spectrum mailbox/worker remain outside main-actor isolation and interact with the control plane only through their preallocated state.

Each analyzer installation receives a monotonically increasing generation. Stop, disablement, graph rebuild, and media-services reset invalidate the current generation. A worker completion carries its submission generation, and `NoiseEngine` invokes `onSpectrumSnapshot` only when that generation is still current, playback is active, and spectrum analysis remains enabled. This rejects results already in flight when a tap is removed.

The tap remains post-EQ and before the main mixer volume. This makes the FFT represent the generated spectral shape. `PlaybackViewModel.masterVolume` separately scales visual response strength so the NOISE knob still affects the ripple without changing the FFT's band ratios.

PHONE volume is intentionally excluded. It controls device playback after Sculptor's generated signal and must not reshape the visual spectrum.

## Component 4 — Playback and lifecycle state (`Sculptor`)

Replace scope-specific view-model state:

- Remove `scopeSamples` and `_ingestScopeSamples(_:)`.
- Add `spectrumSnapshot`, initially `.zero`.
- Add `spectrumReceivedAt: ContinuousClock.Instant?` for the newest snapshot.
- Add `visualizationActive`, controlled by `RootView`.
- Replace `setScopeActive(_:)` with `setVisualizationActive(_:)`.

`PlaybackViewModel` receives engine snapshots on the main actor, guards `isPlaying && visualizationActive`, and stores the newest target and receive time. When playback stops or visualization becomes inactive, it sets the target to `.zero`; the renderer performs the visible release rather than freezing on the last frame.

`RootView` computes visualization activity from:

```text
scenePhase == .active && !showPresets
```

Opening Sculpt does not disable visualization, so the ripple continues in the uncovered Home area around the sheet. `SculptSheet` keeps its existing opaque background; this feature does not make sheet content translucent. Opening the full-screen Presets page disables spectrum analysis and Home rendering. Returning to Home re-enables analysis; if audio is already playing, `NoiseEngine` reinstalls the tap.

## Component 5 — `RippleBackground` (`Sculptor`)

`RippleBackground` is a Home-only SwiftUI view accepting:

- target `SpectrumSnapshot`
- `spectrumReceivedAt: ContinuousClock.Instant?`
- `isPlaying`
- `masterVolume`
- `isActive`
- Reduce Motion state
- Low Power Mode state

It uses `TimelineView(.animation)` to update shader time and calculate interpolated parameters from the current and target spectrum.

Interpolation lives in a pure `RippleAnimationState` value rather than in view-only logic. The state accepts explicit `ContinuousClock.Instant` values for retargeting and evaluation and returns immutable `RippleUniforms`. `RippleBackground` stores that state, retargets it when spectrum, playback, or motion-profile inputs change, and asks it for uniforms using each timeline tick's explicit instant. Unit tests use synthetic instants; no real timers or SwiftUI inspection dependency is required.

### Animation response

- Spectrum updates use a 120 ms attack time and a 450 ms release time.
- Peak accents use a 250 ms release time.
- Each scalar uses an exponential envelope with the applicable attack or release time constant.
- A new target begins from the currently interpolated value, not the preceding target, preventing discontinuities when snapshots arrive faster than a transition completes.
- While playing, a snapshot older than 350 ms is treated as a zero target. The next valid snapshot resumes normal attack interpolation. This prevents a stopped or failed analyzer from freezing the last contour shape.
- Stopping playback targets zero spectral influence but keeps time-based drift active.
- `masterVolume` scales only the audio-driven contribution. At zero NOISE volume, the agreed paused-style baseline remains visible.

The eight bands are packed into two `SIMD4<Float>` values for Metal. Other uniforms are canvas size, elapsed time, RMS, peak, audio-response scale, motion-profile scale, and the DesignSystem accent color.

### Frame cadence

- Normal foreground profile: display animation cadence, targeting 60 fps.
- Low Power Mode: minimum interval of 1/30 second and reduced fine-detail work.
- Reduce Motion: minimum interval of 1/30 second, no peak accents, strongly reduced deformation, and preserved slow drift.
- Inactive: timeline is paused and no shader time advances.

Reduce Motion comes from SwiftUI's `accessibilityReduceMotion` environment value. Low Power Mode is initialized from `ProcessInfo.processInfo.isLowPowerModeEnabled` and updated from `NSProcessInfoPowerStateDidChange` notifications.

## Component 6 — `LivingContours.metal` (`Sculptor`)

Add one stitchable Metal function compiled into the app target's default shader library. It uses the SwiftUI `ShapeStyle` shader contract (`[[ stitchable ]] half4 livingContours(float2 position, ...)`) and renders a transparent procedural field over `DockColor.background`.

The shader uses signed-distance contour bands and low-cost deterministic spatial noise. The normal profile uses two spatial-noise octaves; Low Power Mode and Reduce Motion use one. It does not sample textures, allocate buffers, render particles, or require an offscreen pass.

Audio mapping is fixed as follows:

- 60, 125, and 250 Hz: broad radius, breathing depth, and large-scale spacing.
- 500 Hz, 1 kHz, and 2 kHz: asymmetry, lobe displacement, rotation bias, and drift.
- 4 kHz and 8 kHz: fine edge perturbation and teal glow width.
- RMS: total audio-driven opacity and displacement strength.
- Peak: restrained short-lived highlight accent.

Baseline time functions use staggered 8–14 second cycles to drive slow translation, rotation, and deformation independently of audio. Audio values add to that baseline; they never replace it.

The selected balanced profile uses `0.10` paused line alpha, caps active line alpha at `0.30`, and caps glow alpha at `0.18`. White text, the teal play control, volume knobs, chips, and timer remain legible without adding opaque backing cards.

## Component 7 — Home integration and removals

`HomeView` keeps its existing `ZStack` ordering:

1. `DockColor.background.ignoresSafeArea()`
2. `RippleBackground(...).ignoresSafeArea()`
3. Existing foreground `VStack`

The ripple uses `.allowsHitTesting(false)` and `.accessibilityHidden(true)`.

Remove `ScopeVisualizer(samples:)` from `heroCenter` and remove the knob row's existing extra `.padding(.top, DockSpacing.sm)`. The play button is followed directly by the NOISE/PHONE knob row with exactly the enclosing stack's `DockSpacing.lg` gap. Status and error text remain unchanged.

Delete scope-only implementation after confirming no remaining callers:

- `ScopeVisualizer` and `ScopeGeometry`
- `ScopeVisualizerTests`
- `Downsample` and `DownsampleTests`
- scope sample state and callbacks

Rename scope-tap lifecycle tests to spectrum-tap tests and retain their lifecycle coverage.

## Performance and Real-Time Safety

- The procedural shader is one full-screen GPU pass.
- The FFT setup, Hann window, raw accumulation/mailbox buffers, and intermediate analysis storage are reused.
- The audio tap performs only bounded raw-memory copies, integer bookkeeping private to the producer, and lock-free atomic slot transitions. The polling worker is created before tap installation; the tap performs no wake-up call or per-frame dispatch.
- At most one analysis frame may be pending.
- Graph, tap, analyzer, and generation lifecycle changes are main-actor isolated.
- Late worker completions are discarded by generation and active-state checks.
- No analysis callback mutates SwiftUI state off the main actor.
- Spectrum analysis is disabled when Home is covered by Presets or the scene is inactive.
- Shader animation is paused when inactive and reduced under Low Power Mode.
- Rendering or analysis failure cannot change `NoiseEngine.isPlaying`, the audio graph, sleep-timer behavior, or Now Playing state.

## Error Handling and Fallbacks

- FFT setup failure disables spectrum updates for that analyzer instance and leaves playback untouched.
- Empty, short, malformed, or non-finite input produces finite zeroed values where necessary.
- A dropped analysis frame is expected backpressure, not an error.
- Arbitrary tap callback lengths are accumulated into complete FFT windows without zero-padding normal short callbacks.
- Missing or delayed spectrum updates cause audio-driven influence to release toward zero while baseline drift continues.
- The app build verifies MSL compilation. Because SwiftUI shader lookup and argument binding are dynamic, a simulator/device smoke check must instantiate `RippleBackground` and confirm the shader produces nonempty pixels. Runtime rendering remains decorative and never gates Home interaction or playback.
- Audio start errors continue to use the existing `PlaybackViewModel.errorText` path.

## Testing

### `AudioEngine` unit tests

- A pure sine at each EQ center activates the expected band more strongly than nonadjacent bands.
- Frequencies on geometric boundaries produce stable adjacent-band behavior.
- Mixed tones activate their corresponding bands.
- Silence returns `.zero` within floating-point tolerance.
- White noise produces finite, bounded values.
- RMS and peak are correct for known synthetic input.
- Hann windowing and FFT normalization remain deterministic.
- 44.1 kHz production input and 48 kHz analyzer-level input map bins to the same semantic bands.
- Arbitrary callback chunks assemble exactly into complete 4,096-sample windows without attenuation.
- A callback spanning multiple windows publishes bounded complete windows and preserves its remainder.
- NaN and infinity never escape in a snapshot.
- A busy analyzer drops a submitted frame without blocking.
- Injected analyzer setup failure leaves playback state, the audio graph, sleep-timer state, and Now Playing behavior unchanged.
- Injected analyzer submission failure leaves playback active and falls back to stale-snapshot decay.
- Spectrum tap install/remove, enable/disable, stop, and graph-rebuild behavior remain idempotent.
- A completion from an invalidated generation never reaches the view-model callback.
- Notification-driven interruption, route-change, and media-reset paths hop to the main actor before lifecycle mutation.
- Media-services reset recreates analyzer metadata from the rebuilt 44.1 kHz graph format.
- Mailbox stress tests run under Thread Sanitizer to cover producer/consumer slot transitions and teardown ordering.

### `Sculptor` unit tests

- Spectrum targets update only from engine callbacks.
- Stop and inactive visibility target `.zero`.
- A spectrum target older than 350 ms releases toward zero and a later snapshot resumes attack interpolation.
- Home-active playback re-enables spectrum analysis.
- Sculpt presentation leaves analysis active; Presets presentation disables it.
- Interpolation starts from the current displayed value.
- Attack, release, peak decay, master-volume scaling, and paused baseline values are deterministic.
- Reduce Motion and Low Power Mode produce the intended motion profiles.
- Spectrum-to-uniform packing preserves all eight bands in order.

### Build and visual verification

- Run `Scripts/test-all.sh`, preserving the repository's three-suite coverage after removing obsolete scope/downsample tests and adding spectrum/ripple tests.
- Build the generated workspace for an iOS 17+ simulator to verify Metal compilation.
- Launch a simulator/device smoke host that instantiates `RippleBackground` and confirms runtime shader lookup, argument binding, and visible output.
- Verify on simulator and device:
  - ripple is visible on Home and in the uncovered area around the opaque Sculpt sheet
  - ripple is absent from Presets
  - paused drift is always present
  - every EQ band produces a visible but balanced change
  - NOISE volume scales audio response
  - PHONE volume does not reshape contours
  - foreground controls remain readable
  - entering background stops analysis and rendering
- Profile on device for audio underruns, analysis backlog, and Metal frame time. The analyzer queue must never accumulate work, and normal foreground rendering must sustain display cadence without audio glitches.

## Acceptance Criteria

1. Home contains no oscilloscope line or reserved oscilloscope space.
2. Living contours fill the Home background and match the approved organic direction.
3. Paused contours continue drifting gently at low intensity.
4. Active contours respond to the real post-EQ eight-band spectrum.
5. EQ changes become visibly reflected after the next accepted analysis frame and transition, without abrupt jumps.
6. Response remains balanced: controls and text dominate the visual hierarchy.
7. Sculpt leaves the ripple visible in the uncovered Home area without changing the sheet's opaque background; Presets does not show or continue rendering it.
8. Reduce Motion and Low Power Mode use calmer profiles.
9. Playback remains correct if analysis is unavailable or frames are dropped.
10. All maintained tests pass, the shader compiles, and device profiling shows no audio underruns or analysis backlog.

## Deferred

- User-adjustable ripple intensity.
- Alternate visualizer styles or retained oscilloscope mode.
- Touch-, accelerometer-, or gyroscope-driven deformation.
- Per-preset ripple colors.
- GPU FFT or an all-Metal audio-analysis pipeline.
