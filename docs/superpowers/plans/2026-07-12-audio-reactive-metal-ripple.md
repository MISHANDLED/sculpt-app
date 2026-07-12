# Audio-Reactive Metal Ripple Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Home's oscilloscope with a continuously drifting, post-EQ audio-reactive living-contour background rendered by Metal.

**Architecture:** `AudioEngine` captures arbitrary post-EQ tap chunks into a bounded two-slot lock-free mailbox and analyzes 4,096-sample windows with a reused Accelerate/vDSP FFT. `Sculptor` receives finite eight-band snapshots, applies deterministic time-based envelopes and visibility policy, then passes compact uniforms to a single procedural SwiftUI Metal shader shown only behind Home.

**Tech Stack:** Swift 5 language mode, Swift Testing, AVFAudio, Accelerate/vDSP, local C11 atomics, Swift Concurrency, SwiftUI `TimelineView`, Metal Shading Language, Tuist, iOS 17+

**Spec:** `docs/superpowers/specs/2026-07-12-audio-reactive-metal-ripple-design.md`

## Global Constraints

- Keep `Package.swift` at Swift tools 6.0, iOS 17+, and `swiftLanguageModes: [.v5]`. Add one local C target named `RealtimeAtomics`; do not add a remote package or raise the deployment floor to use iOS 18-only `Synchronization.Atomic`.
- Preserve the no-top-level-free-functions rule for Swift. The `rt_atomic_u8_*` C ABI functions are the narrowly scoped C-shim exception and remain prefixed/internal to the AudioEngine package.
- Keep the production audio graph fixed at stereo 44.1 kHz. Parameterize only the analyzer and test it at 44.1 and 48 kHz.
- Keep dependency direction `Sculptor -> AudioEngine + DesignSystem`; the two packages must not import each other or the app.
- Use the CPU only for FFT analysis and one app-target Metal shader for full-screen rendering.
- The render tap may perform bounded raw-memory copies and atomic transitions only: no FFT, Swift `Array`, heap allocation, lock, semaphore, `Task`, dispatch/wakeup call, ARC ownership change, or blocking wait.
- Preallocate one 4,096-float accumulator, two 4,096-float mailbox slots, FFT/window/split-complex/magnitude storage, and the 60 Hz polling worker before installing the tap.
- Keep only the newest pending complete window; dropping a frame under load is expected and must not affect playback.
- Isolate every `NoiseEngine` graph, tap, analyzer, fade, and generation mutation to `@MainActor`; notification selectors must parse scalar values before hopping to main.
- Reject analyzer completions unless their generation is current and playback plus spectrum analysis are still active.
- Render four translucent contours with `0.10` paused line alpha, active line alpha capped at `0.30`, and glow alpha capped at `0.18`; use no texture, particle system, blur layer, drawing group, Canvas pass, or offscreen render target.
- Keep gentle drift while paused. Low Power Mode and Reduce Motion use 30 fps and one noise octave; Reduce Motion also suppresses peak accents and strongly reduces deformation.
- Only Home owns `RippleBackground`. Sculpt leaves it active behind the existing opaque sheet; Presets and inactive scene phases disable both analysis and rendering.
- The NOISE volume scales only shader response. PHONE hardware volume never alters the snapshot or contour response.
- Use Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`). Tests must never call `engine.start()` or activate a real audio session.
- Redirect every `xcodebuild` invocation to a log file; never pipe live `xcodebuild` output.
- Run `tuist generate --no-open` after adding/removing app or test files so the generated workspace includes them.
- Commit directly on `master` with the repository identity, no push and no co-author trailer.

---

### Task 1: Finite Spectrum Snapshot Contract

**Files:**

- Create: `Packages/AudioEngine/Sources/AudioEngine/SpectrumSnapshot.swift`
- Create: `Packages/AudioEngine/Tests/AudioEngineTests/SpectrumSnapshotTests.swift`

**Interfaces:**

- Consumes: no feature-specific type.
- Produces: `public struct SpectrumSnapshot: Equatable, Sendable`, `init(bands:rms:peak:)`, and `static let zero`.

- [ ] **Step 1: Write the failing value-contract tests**

Create `Packages/AudioEngine/Tests/AudioEngineTests/SpectrumSnapshotTests.swift`:

```swift
import Testing
@testable import AudioEngine

@Suite("Spectrum snapshot")
struct SpectrumSnapshotTests {
    @Test func zeroContainsOnlyZeros() {
        #expect(SpectrumSnapshot.zero.bands == .zero)
        #expect(SpectrumSnapshot.zero.rms == 0)
        #expect(SpectrumSnapshot.zero.peak == 0)
    }

    @Test func initializerClampsFiniteValues() {
        let snapshot = SpectrumSnapshot(
            bands: SIMD8<Float>(-1, 0, 0.25, 0.5, 0.75, 1, 2, 100),
            rms: -0.5,
            peak: 1.5
        )

        #expect(snapshot.bands == SIMD8<Float>(0, 0, 0.25, 0.5, 0.75, 1, 1, 1))
        #expect(snapshot.rms == 0)
        #expect(snapshot.peak == 1)
    }

    @Test func initializerReplacesNonFiniteValuesWithZero() {
        let snapshot = SpectrumSnapshot(
            bands: SIMD8<Float>(
                .nan, .infinity, -.infinity, 0.2, 0.4, 0.6, 0.8, 1
            ),
            rms: .nan,
            peak: .infinity
        )

        #expect(snapshot.bands == SIMD8<Float>(0, 0, 0, 0.2, 0.4, 0.6, 0.8, 1))
        #expect(snapshot.rms == 0)
        #expect(snapshot.peak == 0)
    }
}
```

- [ ] **Step 2: Run the focused test to verify RED**

```bash
cd Packages/AudioEngine
xcodebuild test \
  -scheme AudioEngine \
  -destination "platform=iOS Simulator,name=${SIM:-iPhone 16}" \
  -only-testing:AudioEngineTests/SpectrumSnapshotTests \
  > /tmp/spectrum-snapshot-red.log 2>&1
status=$?
tail -40 /tmp/spectrum-snapshot-red.log
exit $status
```

Expected: build failure because `SpectrumSnapshot` is undefined.

- [ ] **Step 3: Implement the immutable finite value**

Create `Packages/AudioEngine/Sources/AudioEngine/SpectrumSnapshot.swift`:

```swift
public struct SpectrumSnapshot: Equatable, Sendable {
    public let bands: SIMD8<Float>
    public let rms: Float
    public let peak: Float

    public static let zero = SpectrumSnapshot(
        bands: .zero,
        rms: 0,
        peak: 0
    )

    public init(
        bands: SIMD8<Float>,
        rms: Float,
        peak: Float
    ) {
        self.bands = SIMD8<Float>(
            Self.normalized(bands[0]),
            Self.normalized(bands[1]),
            Self.normalized(bands[2]),
            Self.normalized(bands[3]),
            Self.normalized(bands[4]),
            Self.normalized(bands[5]),
            Self.normalized(bands[6]),
            Self.normalized(bands[7])
        )
        self.rms = Self.normalized(rms)
        self.peak = Self.normalized(peak)
    }

    private static func normalized(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }
}
```

- [ ] **Step 4: Run the focused test to verify GREEN**

```bash
cd Packages/AudioEngine
xcodebuild test \
  -scheme AudioEngine \
  -destination "platform=iOS Simulator,name=${SIM:-iPhone 16}" \
  -only-testing:AudioEngineTests/SpectrumSnapshotTests \
  > /tmp/spectrum-snapshot-green.log 2>&1
```

Expected: `SpectrumSnapshotTests` passes.

- [ ] **Step 5: Commit the snapshot contract**

```bash
git add \
  Packages/AudioEngine/Sources/AudioEngine/SpectrumSnapshot.swift \
  Packages/AudioEngine/Tests/AudioEngineTests/SpectrumSnapshotTests.swift
git commit -m "feat(audio): add spectrum snapshot"
```

---

### Task 2: Reusable Accelerate Spectrum Kernel

**Files:**

- Create: `Packages/AudioEngine/Sources/AudioEngine/SpectrumFFT.swift`
- Create: `Packages/AudioEngine/Tests/AudioEngineTests/SpectrumFFTTests.swift`

**Interfaces:**

- Consumes: `SpectrumSnapshot.init(bands:rms:peak:)` from Task 1.
- Produces: internal `final class SpectrumFFT`, `static let sampleCount = 4_096`, `init?(sampleRate:)`, and `analyze(_:) -> SpectrumSnapshot`.

- [ ] **Step 1: Write deterministic FFT and normalization tests**

Create `Packages/AudioEngine/Tests/AudioEngineTests/SpectrumFFTTests.swift`:

```swift
import Foundation
import Testing
@testable import AudioEngine

enum SpectrumTestSignal {
    static func sine(
        frequency: Double,
        sampleRate: Double,
        amplitude: Float = 0.5
    ) -> [Float] {
        (0..<SpectrumFFT.sampleCount).map { index in
            amplitude * sin(2 * .pi * Float(frequency) * Float(index) / Float(sampleRate))
        }
    }

    static func mixed(
        frequencies: [Double],
        sampleRate: Double,
        amplitude: Float = 0.25
    ) -> [Float] {
        (0..<SpectrumFFT.sampleCount).map { index in
            frequencies.reduce(Float.zero) { sum, frequency in
                sum + amplitude * sin(
                    2 * .pi * Float(frequency) * Float(index) / Float(sampleRate)
                )
            }
        }
    }

    static func deterministicNoise() -> [Float] {
        var state: UInt64 = 0x1234_5678_9ABC_DEF0
        return (0..<SpectrumFFT.sampleCount).map { _ in
            state = state &* 6_364_136_223_846_793_005 &+ 1
            let unit = Float(state >> 40) / Float(1 << 24)
            return (unit * 2 - 1) * 0.4
        }
    }

    static func analyze(
        _ samples: [Float],
        sampleRate: Double = 44_100
    ) -> SpectrumSnapshot {
        let fft = SpectrumFFT(sampleRate: sampleRate)!
        return samples.withUnsafeBufferPointer { fft.analyze($0) }
    }
}

@Suite("Spectrum FFT")
struct SpectrumFFTTests {
    private let centers: [Double] = [60, 125, 250, 500, 1_000, 2_000, 4_000, 8_000]

    @Test func silenceProducesZeroSnapshot() {
        let samples = [Float](repeating: 0, count: SpectrumFFT.sampleCount)
        #expect(SpectrumTestSignal.analyze(samples) == .zero)
    }

    @Test func eachEQCenterDominatesNonAdjacentBands() {
        for (index, center) in centers.enumerated() {
            let snapshot = SpectrumTestSignal.analyze(
                SpectrumTestSignal.sine(frequency: center, sampleRate: 44_100)
            )
            let distant = (0..<8)
                .filter { abs($0 - index) > 1 }
                .map { snapshot.bands[$0] }
                .max() ?? 0
            #expect(snapshot.bands[index] > distant + 0.10)
        }
    }

    @Test func geometricBoundaryToneActivatesAdjacentBands() {
        let boundary = sqrt(500.0 * 1_000.0)
        let snapshot = SpectrumTestSignal.analyze(
            SpectrumTestSignal.sine(frequency: boundary, sampleRate: 44_100)
        )
        let nonAdjacent = [snapshot.bands[0], snapshot.bands[1], snapshot.bands[2],
                           snapshot.bands[6], snapshot.bands[7]].max() ?? 0
        #expect(max(snapshot.bands[3], snapshot.bands[4]) > nonAdjacent + 0.10)
        #expect(min(snapshot.bands[3], snapshot.bands[4]) > 0)
    }

    @Test func mixedTonesActivateCorrespondingBands() {
        let snapshot = SpectrumTestSignal.analyze(
            SpectrumTestSignal.mixed(
                frequencies: [125, 2_000],
                sampleRate: 44_100
            )
        )
        #expect(snapshot.bands[1] > snapshot.bands[4])
        #expect(snapshot.bands[5] > snapshot.bands[3])
    }

    @Test func deterministicNoiseProducesFiniteBoundedValues() {
        let snapshot = SpectrumTestSignal.analyze(
            SpectrumTestSignal.deterministicNoise()
        )
        for index in 0..<8 {
            #expect(snapshot.bands[index].isFinite)
            #expect((0...1).contains(snapshot.bands[index]))
        }
        #expect(snapshot.rms.isFinite && (0...1).contains(snapshot.rms))
        #expect(snapshot.peak.isFinite && (0...1).contains(snapshot.peak))
    }

    @Test func knownAmplitudeProducesExpectedRMSAndPeakMappings() {
        let samples = (0..<SpectrumFFT.sampleCount).map { $0.isMultiple(of: 2) ? Float(0.25) : -0.25 }
        let snapshot = SpectrumTestSignal.analyze(samples)
        let expectedRMS = Float((20 * log10(0.25) + 60) / 48)
        let expectedPeak = Float((20 * log10(0.25) + 48) / 42)
        #expect(abs(snapshot.rms - expectedRMS) < 0.001)
        #expect(abs(snapshot.peak - expectedPeak) < 0.001)
    }

    @Test func binCenteredSineHasStableNormalization() {
        let frequency = 44_100.0 * 64.0 / Double(SpectrumFFT.sampleCount)
        let snapshot = SpectrumTestSignal.analyze(
            SpectrumTestSignal.sine(
                frequency: frequency,
                sampleRate: 44_100,
                amplitude: 1
            )
        )
        #expect(snapshot.bands[3] > 0.70)
    }

    @Test func repeatedAnalysisIsDeterministic() {
        let fft = SpectrumFFT(sampleRate: 44_100)!
        let samples = SpectrumTestSignal.sine(frequency: 1_000, sampleRate: 44_100)
        let first = samples.withUnsafeBufferPointer { fft.analyze($0) }
        let second = samples.withUnsafeBufferPointer { fft.analyze($0) }
        #expect(first == second)
    }

    @Test func semanticBandsMatchAt44100And48000() {
        let at44100 = SpectrumTestSignal.analyze(
            SpectrumTestSignal.sine(frequency: 1_000, sampleRate: 44_100),
            sampleRate: 44_100
        )
        let at48000 = SpectrumTestSignal.analyze(
            SpectrumTestSignal.sine(frequency: 1_000, sampleRate: 48_000),
            sampleRate: 48_000
        )
        let max44100 = (0..<8).map { at44100.bands[$0] }.max()
        let max48000 = (0..<8).map { at48000.bands[$0] }.max()
        #expect(at44100.bands[4] == max44100)
        #expect(at48000.bands[4] == max48000)
    }

    @Test func shortInputProducesZero() {
        let fft = SpectrumFFT(sampleRate: 44_100)!
        let samples = [Float](repeating: 1, count: 128)
        let snapshot = samples.withUnsafeBufferPointer { fft.analyze($0) }
        #expect(snapshot == .zero)
    }

    @Test func nonFiniteInputCannotEscapeSnapshot() {
        var samples = SpectrumTestSignal.sine(frequency: 500, sampleRate: 44_100)
        samples[10] = .nan
        samples[20] = .infinity
        let snapshot = SpectrumTestSignal.analyze(samples)
        #expect((0..<8).allSatisfy { snapshot.bands[$0].isFinite })
        #expect(snapshot.rms.isFinite)
        #expect(snapshot.peak.isFinite)
    }
}
```

- [ ] **Step 2: Run the focused test to verify RED**

```bash
cd Packages/AudioEngine
xcodebuild test \
  -scheme AudioEngine \
  -destination "platform=iOS Simulator,name=${SIM:-iPhone 16}" \
  -only-testing:AudioEngineTests/SpectrumFFTTests \
  > /tmp/spectrum-fft-red.log 2>&1
status=$?
tail -60 /tmp/spectrum-fft-red.log
exit $status
```

Expected: build failure because `SpectrumFFT` is undefined.

- [ ] **Step 3: Implement the preallocated vDSP kernel**

Create `Packages/AudioEngine/Sources/AudioEngine/SpectrumFFT.swift`:

```swift
import Accelerate
import Foundation

final class SpectrumFFT {
    static let sampleCount = 4_096

    private static let log2Count = vDSP_Length(12)
    private static let centers: [Double] = [
        60, 125, 250, 500, 1_000, 2_000, 4_000, 8_000
    ]

    private let setup: FFTSetup
    private let bandRanges: [Range<Int>]
    private let coherentGain: Float
    private var timeDomain = [Float](repeating: 0, count: sampleCount)
    private var window = [Float](repeating: 0, count: sampleCount)
    private var windowed = [Float](repeating: 0, count: sampleCount)
    private var splitReal = [Float](repeating: 0, count: sampleCount / 2)
    private var splitImag = [Float](repeating: 0, count: sampleCount / 2)
    private var powers = [Float](repeating: 0, count: sampleCount / 2)

    init?(sampleRate: Double) {
        guard sampleRate.isFinite, sampleRate >= 16_000,
              let setup = vDSP_create_fftsetup(Self.log2Count, FFTRadix(kFFTRadix2)) else {
            return nil
        }
        self.setup = setup

        vDSP_hann_window(
            &window,
            vDSP_Length(Self.sampleCount),
            Int32(vDSP_HANN_NORM)
        )
        var gain: Float = 0
        vDSP_meanv(window, 1, &gain, vDSP_Length(Self.sampleCount))
        coherentGain = gain

        let interior = zip(Self.centers, Self.centers.dropFirst()).map { pair in
            sqrt(pair.0 * pair.1)
        }
        let edges = [20.0] + interior + [min(12_000, sampleRate / 2)]
        let binWidth = sampleRate / Double(Self.sampleCount)
        bandRanges = (0..<8).map { index in
            let first = max(1, Int(ceil(edges[index] / binWidth)))
            let end = min(
                Self.sampleCount / 2,
                max(first + 1, Int(ceil(edges[index + 1] / binWidth)))
            )
            return first..<end
        }
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
    }

    func analyze(
        _ samples: UnsafeBufferPointer<Float>
    ) -> SpectrumSnapshot {
        guard samples.count == Self.sampleCount else { return .zero }

        for index in 0..<Self.sampleCount {
            let value = samples[index]
            timeDomain[index] = value.isFinite ? value : 0
        }

        var rms: Float = 0
        var peak: Float = 0
        vDSP_rmsqv(timeDomain, 1, &rms, vDSP_Length(Self.sampleCount))
        vDSP_maxmgv(timeDomain, 1, &peak, vDSP_Length(Self.sampleCount))
        vDSP_vmul(
            timeDomain,
            1,
            window,
            1,
            &windowed,
            1,
            vDSP_Length(Self.sampleCount)
        )

        splitReal.withUnsafeMutableBufferPointer { real in
            splitImag.withUnsafeMutableBufferPointer { imaginary in
                var split = DSPSplitComplex(
                    realp: real.baseAddress!,
                    imagp: imaginary.baseAddress!
                )
                windowed.withUnsafeBytes { bytes in
                    let complex = bytes.bindMemory(to: DSPComplex.self)
                    vDSP_ctoz(
                        complex.baseAddress!,
                        2,
                        &split,
                        1,
                        vDSP_Length(Self.sampleCount / 2)
                    )
                }
                vDSP_fft_zrip(
                    setup,
                    &split,
                    1,
                    Self.log2Count,
                    FFTDirection(FFT_FORWARD)
                )
                vDSP_zvmags(
                    &split,
                    1,
                    &powers,
                    1,
                    vDSP_Length(Self.sampleCount / 2)
                )
            }
        }

        // vDSP_fft_zrip doubles the conventional positive-frequency
        // coefficient, so N × coherent gain recovers peak amplitude.
        let amplitudeScale = 1 / (Float(Self.sampleCount) * coherentGain)
        var powerScale = amplitudeScale * amplitudeScale
        vDSP_vsmul(
            powers,
            1,
            &powerScale,
            &powers,
            1,
            vDSP_Length(Self.sampleCount / 2)
        )

        var bands = SIMD8<Float>.zero
        for (index, range) in bandRanges.enumerated() {
            var mean: Float = 0
            powers.withUnsafeBufferPointer { buffer in
                vDSP_meanv(
                    buffer.baseAddress! + range.lowerBound,
                    1,
                    &mean,
                    vDSP_Length(range.count)
                )
            }
            bands[index] = Self.mapPower(mean, floorDB: -72, ceilingDB: -12)
        }

        return SpectrumSnapshot(
            bands: bands,
            rms: Self.mapAmplitude(rms, floorDB: -60, ceilingDB: -12),
            peak: Self.mapAmplitude(peak, floorDB: -48, ceilingDB: -6)
        )
    }

    private static func mapPower(
        _ power: Float,
        floorDB: Float,
        ceilingDB: Float
    ) -> Float {
        let dB = 10 * log10(max(power, 1e-12))
        return normalized(dB, floorDB: floorDB, ceilingDB: ceilingDB)
    }

    private static func mapAmplitude(
        _ amplitude: Float,
        floorDB: Float,
        ceilingDB: Float
    ) -> Float {
        let dB = 20 * log10(max(amplitude, 1e-6))
        return normalized(dB, floorDB: floorDB, ceilingDB: ceilingDB)
    }

    private static func normalized(
        _ dB: Float,
        floorDB: Float,
        ceilingDB: Float
    ) -> Float {
        min(1, max(0, (dB - floorDB) / (ceilingDB - floorDB)))
    }
}
```

- [ ] **Step 4: Run the focused test to verify GREEN**

```bash
cd Packages/AudioEngine
xcodebuild test \
  -scheme AudioEngine \
  -destination "platform=iOS Simulator,name=${SIM:-iPhone 16}" \
  -only-testing:AudioEngineTests/SpectrumFFTTests \
  > /tmp/spectrum-fft-green.log 2>&1
```

Expected: `SpectrumFFTTests` passes at both supported analyzer sample rates.

- [ ] **Step 5: Commit the FFT kernel**

```bash
git add \
  Packages/AudioEngine/Sources/AudioEngine/SpectrumFFT.swift \
  Packages/AudioEngine/Tests/AudioEngineTests/SpectrumFFTTests.swift
git commit -m "feat(audio): add FFT spectrum analysis"
```

---

### Task 3: Bounded Real-Time Spectrum Mailbox

**Files:**

- Modify: `Packages/AudioEngine/Package.swift`
- Create: `Packages/AudioEngine/Sources/RealtimeAtomics/include/RealtimeAtomics.h`
- Create: `Packages/AudioEngine/Sources/RealtimeAtomics/RealtimeAtomics.c`
- Create: `Packages/AudioEngine/Sources/AudioEngine/SpectrumMailbox.swift`
- Create: `Packages/AudioEngine/Tests/AudioEngineTests/SpectrumMailboxTests.swift`

**Interfaces:**

- Consumes: fixed `SpectrumFFT.sampleCount == 4_096` from Task 2.
- Produces: local C11 atomic-cell functions plus failable `SpectrumMailbox.init?()`, `opaqueContext`, static `submit(context:samples:count:)`, `claimLatest()`, `release(_:)`, and `ClaimedSpectrumFrame`.

- [ ] **Step 1: Write accumulation, latest-frame, and ownership tests**

Create `Packages/AudioEngine/Tests/AudioEngineTests/SpectrumMailboxTests.swift`:

```swift
import Foundation
import Testing
@testable import AudioEngine

enum SpectrumMailboxTestSupport {
    @discardableResult
    static func submit(
        _ values: ArraySlice<Float>,
        to mailbox: SpectrumMailbox
    ) -> Bool {
        values.withUnsafeBufferPointer { buffer in
            SpectrumMailbox.submit(
                context: mailbox.opaqueContext,
                samples: buffer.baseAddress!,
                count: buffer.count
            )
        }
    }

    static func constantWindow(_ value: Float) -> [Float] {
        [Float](repeating: value, count: SpectrumMailbox.sampleCount)
    }

    static func makeMailbox() throws -> SpectrumMailbox {
        try #require(SpectrumMailbox())
    }
}

final class SpectrumMailboxStressState: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    func markFinished() {
        lock.lock()
        finished = true
        lock.unlock()
    }

    func isFinished() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished
    }
}

@Suite("Spectrum mailbox")
struct SpectrumMailboxTests {
    @Test func platformAtomicCellsAreLockFree() throws {
        let mailbox = try SpectrumMailboxTestSupport.makeMailbox()
        #expect(mailbox.isLockFree)
    }

    @Test func arbitraryChunksAssembleOneExactWindow() throws {
        let mailbox = try SpectrumMailboxTestSupport.makeMailbox()
        let input = (0..<SpectrumMailbox.sampleCount).map(Float.init)

        #expect(!SpectrumMailboxTestSupport.submit(input[0..<997], to: mailbox))
        #expect(!SpectrumMailboxTestSupport.submit(input[997..<3_111], to: mailbox))
        #expect(SpectrumMailboxTestSupport.submit(input[3_111..<4_096], to: mailbox))

        let frame = mailbox.claimLatest()
        #expect(frame?.sequence == 1)
        #expect(frame?.samples.first == 0)
        #expect(frame?.samples.last == 4_095)
        if let frame { mailbox.release(frame) }
    }

    @Test func multiWindowSubmissionKeepsNewestAndPreservesRemainder() throws {
        let mailbox = try SpectrumMailboxTestSupport.makeMailbox()
        let input = (0..<9_000).map(Float.init)

        #expect(SpectrumMailboxTestSupport.submit(input[...], to: mailbox))
        let second = mailbox.claimLatest()
        #expect(second?.sequence == 2)
        #expect(second?.samples.first == 4_096)
        #expect(second?.samples.last == 8_191)
        if let second { mailbox.release(second) }

        let completion = [Float](repeating: -1, count: 3_288)
        #expect(SpectrumMailboxTestSupport.submit(completion[...], to: mailbox))
        let third = mailbox.claimLatest()
        #expect(third?.sequence == 3)
        #expect(third?.samples.first == 8_192)
        #expect(third?.samples[807] == 8_999)
        #expect(third?.samples[808] == -1)
        if let third { mailbox.release(third) }
    }

    @Test func readyFrameIsOverwrittenByNewerFrame() throws {
        let mailbox = try SpectrumMailboxTestSupport.makeMailbox()
        let first = SpectrumMailboxTestSupport.constantWindow(1)
        let second = SpectrumMailboxTestSupport.constantWindow(2)
        #expect(SpectrumMailboxTestSupport.submit(first[...], to: mailbox))
        #expect(SpectrumMailboxTestSupport.submit(second[...], to: mailbox))

        let frame = mailbox.claimLatest()
        #expect(frame?.sequence == 2)
        #expect(frame?.samples.allSatisfy { $0 == 2 } == true)
        if let frame { mailbox.release(frame) }
    }

    @Test func submissionDropsImmediatelyWhenBothSlotsAreReading() throws {
        let mailbox = try SpectrumMailboxTestSupport.makeMailbox()
        let firstValues = SpectrumMailboxTestSupport.constantWindow(1)
        let secondValues = SpectrumMailboxTestSupport.constantWindow(2)
        let thirdValues = SpectrumMailboxTestSupport.constantWindow(3)

        #expect(SpectrumMailboxTestSupport.submit(firstValues[...], to: mailbox))
        let first = mailbox.claimLatest()!
        #expect(SpectrumMailboxTestSupport.submit(secondValues[...], to: mailbox))
        let second = mailbox.claimLatest()!

        #expect(!SpectrumMailboxTestSupport.submit(thirdValues[...], to: mailbox))
        mailbox.release(first)
        mailbox.release(second)
    }

    @Test func producerNeverMutatesAClaimedFrame() throws {
        let mailbox = try SpectrumMailboxTestSupport.makeMailbox()
        let firstValues = SpectrumMailboxTestSupport.constantWindow(1)
        let secondValues = SpectrumMailboxTestSupport.constantWindow(2)
        let thirdValues = SpectrumMailboxTestSupport.constantWindow(3)

        #expect(SpectrumMailboxTestSupport.submit(firstValues[...], to: mailbox))
        let claimed = mailbox.claimLatest()!
        #expect(SpectrumMailboxTestSupport.submit(secondValues[...], to: mailbox))
        #expect(SpectrumMailboxTestSupport.submit(thirdValues[...], to: mailbox))
        #expect(claimed.samples.allSatisfy { $0 == 1 })
        mailbox.release(claimed)
        if let pending = mailbox.claimLatest() { mailbox.release(pending) }
    }

    @Test func concurrentProducerConsumerNeverObservesTornFrames() async throws {
        let mailbox = try SpectrumMailboxTestSupport.makeMailbox()
        let state = SpectrumMailboxStressState()

        let producer = Task.detached {
            for value in 1...2_000 {
                let window = SpectrumMailboxTestSupport.constantWindow(Float(value))
                _ = SpectrumMailboxTestSupport.submit(window[...], to: mailbox)
            }
            state.markFinished()
        }

        let consumer = Task.detached { () -> Bool in
            var torn = false
            while !state.isFinished() {
                guard let frame = mailbox.claimLatest() else { continue }
                let expected = frame.samples[0]
                if !frame.samples.allSatisfy({ $0 == expected }) { torn = true }
                mailbox.release(frame)
            }
            if let frame = mailbox.claimLatest() {
                let expected = frame.samples[0]
                if !frame.samples.allSatisfy({ $0 == expected }) { torn = true }
                mailbox.release(frame)
            }
            return torn
        }

        await producer.value
        #expect(await consumer.value == false)
    }
}
```

- [ ] **Step 2: Run the mailbox test to verify RED**

```bash
cd Packages/AudioEngine
xcodebuild test \
  -scheme AudioEngine \
  -destination "platform=iOS Simulator,name=${SIM:-iPhone 16}" \
  -only-testing:AudioEngineTests/SpectrumMailboxTests \
  > /tmp/spectrum-mailbox-red.log 2>&1
status=$?
tail -60 /tmp/spectrum-mailbox-red.log
exit $status
```

Expected: build failure because `SpectrumMailbox` and `ClaimedSpectrumFrame` are undefined.

- [ ] **Step 3: Add the iOS 17-compatible local C11 atomic target**

Replace `Packages/AudioEngine/Package.swift` with:

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
        .target(
            name: "RealtimeAtomics",
            path: "Sources/RealtimeAtomics",
            publicHeadersPath: "include"
        ),
        .target(
            name: "AudioEngine",
            dependencies: ["RealtimeAtomics"]
        ),
        .testTarget(
            name: "AudioEngineTests",
            dependencies: ["AudioEngine"]
        )
    ],
    swiftLanguageModes: [.v5]
)
```

Create `Packages/AudioEngine/Sources/RealtimeAtomics/include/RealtimeAtomics.h`:

```c
#ifndef REALTIME_ATOMICS_H
#define REALTIME_ATOMICS_H

#include <stdbool.h>
#include <stdint.h>

#if defined(__cplusplus)
extern "C" {
#endif

typedef struct RTAtomicUInt8 RTAtomicUInt8;

RTAtomicUInt8 *rt_atomic_u8_create(uint8_t initial_value);
void rt_atomic_u8_destroy(RTAtomicUInt8 *atomic_value);
uint8_t rt_atomic_u8_load_acquire(const RTAtomicUInt8 *atomic_value);
bool rt_atomic_u8_is_lock_free(const RTAtomicUInt8 *atomic_value);
void rt_atomic_u8_store_release(
    RTAtomicUInt8 *atomic_value,
    uint8_t desired
);
bool rt_atomic_u8_compare_exchange_acq_rel(
    RTAtomicUInt8 *atomic_value,
    uint8_t expected,
    uint8_t desired
);
uint8_t rt_atomic_u8_exchange_acq_rel(
    RTAtomicUInt8 *atomic_value,
    uint8_t desired
);

#if defined(__cplusplus)
}
#endif

#endif
```

Create `Packages/AudioEngine/Sources/RealtimeAtomics/RealtimeAtomics.c`:

```c
#include "RealtimeAtomics.h"

#include <stdatomic.h>
#include <stdlib.h>

struct RTAtomicUInt8 {
    _Atomic uint8_t value;
};

RTAtomicUInt8 *rt_atomic_u8_create(uint8_t initial_value) {
    RTAtomicUInt8 *atomic_value = malloc(sizeof(RTAtomicUInt8));
    if (atomic_value == NULL) {
        return NULL;
    }
    atomic_init(&atomic_value->value, initial_value);
    return atomic_value;
}

void rt_atomic_u8_destroy(RTAtomicUInt8 *atomic_value) {
    free(atomic_value);
}

uint8_t rt_atomic_u8_load_acquire(const RTAtomicUInt8 *atomic_value) {
    return atomic_load_explicit(
        &atomic_value->value,
        memory_order_acquire
    );
}

bool rt_atomic_u8_is_lock_free(const RTAtomicUInt8 *atomic_value) {
    return atomic_is_lock_free(&atomic_value->value);
}

void rt_atomic_u8_store_release(
    RTAtomicUInt8 *atomic_value,
    uint8_t desired
) {
    atomic_store_explicit(
        &atomic_value->value,
        desired,
        memory_order_release
    );
}

bool rt_atomic_u8_compare_exchange_acq_rel(
    RTAtomicUInt8 *atomic_value,
    uint8_t expected,
    uint8_t desired
) {
    return atomic_compare_exchange_strong_explicit(
        &atomic_value->value,
        &expected,
        desired,
        memory_order_acq_rel,
        memory_order_acquire
    );
}

uint8_t rt_atomic_u8_exchange_acq_rel(
    RTAtomicUInt8 *atomic_value,
    uint8_t desired
) {
    return atomic_exchange_explicit(
        &atomic_value->value,
        desired,
        memory_order_acq_rel
    );
}
```

The C target exists because `Synchronization.Atomic` is unavailable below iOS 18. Every allocation above occurs while constructing the analyzer, before the audio tap exists.

- [ ] **Step 4: Implement fixed raw storage and C11 slot transitions**

Create `Packages/AudioEngine/Sources/AudioEngine/SpectrumMailbox.swift`:

```swift
import Darwin
import RealtimeAtomics

struct ClaimedSpectrumFrame: @unchecked Sendable {
    fileprivate let slot: Int
    let sequence: UInt64
    let samples: UnsafeBufferPointer<Float>
}

final class SpectrumMailbox: @unchecked Sendable {
    static let sampleCount = 4_096

    private static let free: UInt8 = 0
    private static let writing: UInt8 = 1
    private static let ready: UInt8 = 2
    private static let reading: UInt8 = 3

    private let accumulator: UnsafeMutablePointer<Float>
    private let slot0: UnsafeMutablePointer<Float>
    private let slot1: UnsafeMutablePointer<Float>
    private let state0: OpaquePointer
    private let state1: OpaquePointer

    // Producer-only fields; AVAudioNode serializes a tap callback per bus.
    private var accumulatedCount = 0
    private var nextSequence: UInt64 = 0
    private var sequence0: UInt64 = 0
    private var sequence1: UInt64 = 0

    init?() {
        guard let firstState = rt_atomic_u8_create(Self.free) else {
            return nil
        }
        guard rt_atomic_u8_is_lock_free(firstState) else {
            rt_atomic_u8_destroy(firstState)
            return nil
        }
        guard let secondState = rt_atomic_u8_create(Self.free) else {
            rt_atomic_u8_destroy(firstState)
            return nil
        }
        guard rt_atomic_u8_is_lock_free(secondState) else {
            rt_atomic_u8_destroy(firstState)
            rt_atomic_u8_destroy(secondState)
            return nil
        }

        state0 = firstState
        state1 = secondState
        accumulator = .allocate(capacity: Self.sampleCount)
        slot0 = .allocate(capacity: Self.sampleCount)
        slot1 = .allocate(capacity: Self.sampleCount)
    }

    var opaqueContext: UnsafeMutableRawPointer {
        Unmanaged.passUnretained(self).toOpaque()
    }

    var isLockFree: Bool {
        rt_atomic_u8_is_lock_free(state0)
            && rt_atomic_u8_is_lock_free(state1)
    }

    deinit {
        rt_atomic_u8_destroy(state0)
        rt_atomic_u8_destroy(state1)
        accumulator.deallocate()
        slot0.deallocate()
        slot1.deallocate()
    }

    @discardableResult
    static func submit(
        context: UnsafeMutableRawPointer,
        samples: UnsafePointer<Float>,
        count: Int
    ) -> Bool {
        guard count > 0 else { return false }
        let mailbox = Unmanaged<SpectrumMailbox>
            .fromOpaque(context)
            .takeUnretainedValue()
        return mailbox.copyAndPublish(samples: samples, count: count)
    }

    func claimLatest() -> ClaimedSpectrumFrame? {
        var first: ClaimedSpectrumFrame?
        var second: ClaimedSpectrumFrame?

        if rt_atomic_u8_compare_exchange_acq_rel(
            state0,
            Self.ready,
            Self.reading
        ) {
            first = ClaimedSpectrumFrame(
                slot: 0,
                sequence: sequence0,
                samples: UnsafeBufferPointer(start: slot0, count: Self.sampleCount)
            )
        }

        if rt_atomic_u8_compare_exchange_acq_rel(
            state1,
            Self.ready,
            Self.reading
        ) {
            second = ClaimedSpectrumFrame(
                slot: 1,
                sequence: sequence1,
                samples: UnsafeBufferPointer(start: slot1, count: Self.sampleCount)
            )
        }

        switch (first, second) {
        case let (left?, right?):
            if left.sequence > right.sequence {
                release(right)
                return left
            }
            release(left)
            return right
        case let (left?, nil):
            return left
        case let (nil, right?):
            return right
        case (nil, nil):
            return nil
        }
    }

    func release(_ frame: ClaimedSpectrumFrame) {
        if frame.slot == 0 {
            rt_atomic_u8_store_release(state0, Self.free)
        } else {
            rt_atomic_u8_store_release(state1, Self.free)
        }
    }

    private func copyAndPublish(
        samples: UnsafePointer<Float>,
        count: Int
    ) -> Bool {
        var sourceOffset = 0
        var published = false

        while sourceOffset < count {
            let copyCount = min(
                Self.sampleCount - accumulatedCount,
                count - sourceOffset
            )
            memcpy(
                accumulator.advanced(by: accumulatedCount),
                samples.advanced(by: sourceOffset),
                copyCount * MemoryLayout<Float>.stride
            )
            accumulatedCount += copyCount
            sourceOffset += copyCount

            if accumulatedCount == Self.sampleCount {
                published = publishAccumulator() || published
                accumulatedCount = 0
            }
        }

        return published
    }

    private func publishAccumulator() -> Bool {
        // Overwrite a pending ready frame before taking a free slot.
        if rt_atomic_u8_compare_exchange_acq_rel(
            state0,
            Self.ready,
            Self.writing
        ) {
            finishPublish(to: 0)
            return true
        }
        if rt_atomic_u8_compare_exchange_acq_rel(
            state1,
            Self.ready,
            Self.writing
        ) {
            finishPublish(to: 1)
            return true
        }
        if rt_atomic_u8_compare_exchange_acq_rel(
            state0,
            Self.free,
            Self.writing
        ) {
            finishPublish(to: 0)
            return true
        }
        if rt_atomic_u8_compare_exchange_acq_rel(
            state1,
            Self.free,
            Self.writing
        ) {
            finishPublish(to: 1)
            return true
        }
        return false
    }

    private func finishPublish(to slot: Int) {
        nextSequence &+= 1
        if slot == 0 {
            memcpy(
                slot0,
                accumulator,
                Self.sampleCount * MemoryLayout<Float>.stride
            )
            sequence0 = nextSequence
            rt_atomic_u8_store_release(state0, Self.ready)
        } else {
            memcpy(
                slot1,
                accumulator,
                Self.sampleCount * MemoryLayout<Float>.stride
            )
            sequence1 = nextSequence
            rt_atomic_u8_store_release(state1, Self.ready)
        }
    }
}
```

The two C11 atomic cells remain explicit stored properties. Producer publication writes samples and sequence before the release-store to `ready`; consumer access starts only after an acquire-release `ready -> reading` compare-exchange. No C allocation or destruction occurs in `submit`.

- [ ] **Step 5: Run normal and Thread Sanitizer checks**

```bash
cd Packages/AudioEngine
xcodebuild test \
  -scheme AudioEngine \
  -destination "platform=iOS Simulator,name=${SIM:-iPhone 16}" \
  -only-testing:AudioEngineTests/SpectrumMailboxTests \
  > /tmp/spectrum-mailbox-green.log 2>&1

xcodebuild test \
  -scheme AudioEngine \
  -destination "platform=iOS Simulator,name=${SIM:-iPhone 16}" \
  -enableThreadSanitizer YES \
  -only-testing:AudioEngineTests/SpectrumMailboxTests \
  > /tmp/spectrum-mailbox-tsan.log 2>&1
```

Expected: both invocations succeed and the TSan log contains no data-race report.

- [ ] **Step 6: Commit the mailbox and local atomic target**

```bash
git add \
  Packages/AudioEngine/Package.swift \
  Packages/AudioEngine/Sources/RealtimeAtomics/include/RealtimeAtomics.h \
  Packages/AudioEngine/Sources/RealtimeAtomics/RealtimeAtomics.c \
  Packages/AudioEngine/Sources/AudioEngine/SpectrumMailbox.swift \
  Packages/AudioEngine/Tests/AudioEngineTests/SpectrumMailboxTests.swift
git commit -m "feat(audio): add real-time spectrum mailbox"
```

---

### Task 4: Polling Spectrum Analyzer Worker

**Files:**

- Create: `Packages/AudioEngine/Sources/AudioEngine/SpectrumAnalyzer.swift`
- Create: `Packages/AudioEngine/Tests/AudioEngineTests/SpectrumAnalyzerTests.swift`

**Interfaces:**

- Consumes: `SpectrumMailbox`, `ClaimedSpectrumFrame`, `SpectrumFFT`, and `SpectrumSnapshot` from Tasks 1–3.
- Produces: `SpectrumSubmission`, `SpectrumAnalyzing`, `SpectrumAnalyzer`, and `SpectrumAnalyzerFactory` for `NoiseEngine` injection.

- [ ] **Step 1: Write polling, generation, and shutdown tests**

Create `Packages/AudioEngine/Tests/AudioEngineTests/SpectrumAnalyzerTests.swift`:

```swift
import Dispatch
import Foundation
import Testing
@testable import AudioEngine

final class SpectrumAnalyzerDeliveryState: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    func value() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

@Suite("Spectrum analyzer worker")
struct SpectrumAnalyzerTests {
    @Test func pollingWorkerDeliversSnapshotWithGeneration() async throws {
        let samples = SpectrumTestSignal.sine(
            frequency: 1_000,
            sampleRate: 44_100
        )

        await confirmation("spectrum delivered", expectedCount: 1) { delivered in
            let analyzer = SpectrumAnalyzer(
                sampleRate: 44_100,
                generation: 42,
                pollInterval: .milliseconds(1)
            ) { snapshot, generation in
                #expect(generation == 42)
                #expect(snapshot.bands[4] > 0)
                delivered()
            }!

            samples.withUnsafeBufferPointer { buffer in
                _ = analyzer.submission.submit(
                    buffer.baseAddress!,
                    count: buffer.count
                )
            }
            try? await Task.sleep(for: .milliseconds(50))
            analyzer.shutdown()
        }
    }

    @Test func analyzerAccumulatesArbitraryCallbackChunks() async {
        let samples = SpectrumTestSignal.sine(
            frequency: 500,
            sampleRate: 44_100
        )

        await confirmation("one complete window", expectedCount: 1) { delivered in
            let analyzer = SpectrumAnalyzer(
                sampleRate: 44_100,
                generation: 7,
                pollInterval: .milliseconds(1)
            ) { _, generation in
                #expect(generation == 7)
                delivered()
            }!

            samples[0..<777].withUnsafeBufferPointer { buffer in
                _ = analyzer.submission.submit(buffer.baseAddress!, count: buffer.count)
            }
            samples[777..<3_000].withUnsafeBufferPointer { buffer in
                _ = analyzer.submission.submit(buffer.baseAddress!, count: buffer.count)
            }
            samples[3_000..<4_096].withUnsafeBufferPointer { buffer in
                _ = analyzer.submission.submit(buffer.baseAddress!, count: buffer.count)
            }
            try? await Task.sleep(for: .milliseconds(50))
            analyzer.shutdown()
        }
    }

    @Test func shutdownJoinsWorkerAndIsIdempotent() async throws {
        let state = SpectrumAnalyzerDeliveryState()
        let analyzer = SpectrumAnalyzer(
            sampleRate: 44_100,
            generation: 1,
            pollInterval: .milliseconds(1)
        ) { _, _ in
            state.increment()
        }!
        let submission = analyzer.submission
        let samples = SpectrumTestSignal.sine(
            frequency: 2_000,
            sampleRate: 44_100
        )

        samples.withUnsafeBufferPointer { buffer in
            _ = submission.submit(buffer.baseAddress!, count: buffer.count)
        }
        try await Task.sleep(for: .milliseconds(20))
        analyzer.shutdown()
        analyzer.shutdown()
        let countAtShutdown = state.value()

        samples.withUnsafeBufferPointer { buffer in
            _ = submission.submit(buffer.baseAddress!, count: buffer.count)
        }
        try await Task.sleep(for: .milliseconds(20))
        #expect(state.value() == countAtShutdown)
    }

    @Test func shutdownWaitsForInFlightDeliveryBeforeDestruction() async throws {
        let enteredDelivery = DispatchSemaphore(value: 0)
        let releaseDelivery = DispatchSemaphore(value: 0)
        let shutdownState = SpectrumAnalyzerDeliveryState()
        let analyzer = SpectrumAnalyzer(
            sampleRate: 44_100,
            generation: 9,
            pollInterval: .milliseconds(1)
        ) { _, _ in
            enteredDelivery.signal()
            releaseDelivery.wait()
        }!
        let samples = SpectrumTestSignal.sine(
            frequency: 4_000,
            sampleRate: 44_100
        )
        samples.withUnsafeBufferPointer { buffer in
            _ = analyzer.submission.submit(
                buffer.baseAddress!,
                count: buffer.count
            )
        }

        #expect(enteredDelivery.wait(timeout: .now() + 1) == .success)
        let shutdown = Task.detached {
            analyzer.shutdown()
            shutdownState.increment()
        }
        try await Task.sleep(for: .milliseconds(10))
        #expect(shutdownState.value() == 0)

        releaseDelivery.signal()
        await shutdown.value
        #expect(shutdownState.value() == 1)
    }

    @Test func invalidSampleRateFailsSetupWithoutAWorker() {
        let analyzer = SpectrumAnalyzer(
            sampleRate: 0,
            generation: 1,
            pollInterval: .milliseconds(1)
        ) { _, _ in }
        #expect(analyzer == nil)
    }
}
```

- [ ] **Step 2: Run the analyzer test to verify RED**

```bash
cd Packages/AudioEngine
xcodebuild test \
  -scheme AudioEngine \
  -destination "platform=iOS Simulator,name=${SIM:-iPhone 16}" \
  -only-testing:AudioEngineTests/SpectrumAnalyzerTests \
  > /tmp/spectrum-analyzer-red.log 2>&1
status=$?
tail -60 /tmp/spectrum-analyzer-red.log
exit $status
```

Expected: build failure because the analyzer types are undefined.

- [ ] **Step 3: Implement the prestarted 60 Hz polling worker**

Create `Packages/AudioEngine/Sources/AudioEngine/SpectrumAnalyzer.swift`:

```swift
import Dispatch
import RealtimeAtomics

struct SpectrumSubmission: @unchecked Sendable {
    let context: UnsafeMutableRawPointer
    private let function: @Sendable (
        UnsafeMutableRawPointer,
        UnsafePointer<Float>,
        Int
    ) -> Bool

    init(
        context: UnsafeMutableRawPointer,
        function: @escaping @Sendable (
            UnsafeMutableRawPointer,
            UnsafePointer<Float>,
            Int
        ) -> Bool
    ) {
        self.context = context
        self.function = function
    }

    @discardableResult
    func submit(
        _ samples: UnsafePointer<Float>,
        count: Int
    ) -> Bool {
        function(context, samples, count)
    }
}

protocol SpectrumAnalyzing: AnyObject {
    var submission: SpectrumSubmission { get }
    func shutdown()
}

typealias SpectrumAnalyzerFactory = @MainActor (
    Double,
    UInt64,
    @escaping @Sendable (SpectrumSnapshot, UInt64) -> Void
) -> (any SpectrumAnalyzing)?

final class SpectrumAnalyzer: SpectrumAnalyzing, @unchecked Sendable {
    let submission: SpectrumSubmission

    private let generation: UInt64
    private let deliver: @Sendable (SpectrumSnapshot, UInt64) -> Void
    private let mailbox: SpectrumMailbox
    private let fft: SpectrumFFT
    private let queue: DispatchQueue
    private let timer: DispatchSourceTimer
    private let stopped: OpaquePointer

    convenience init?(
        sampleRate: Double,
        generation: UInt64,
        deliver: @escaping @Sendable (SpectrumSnapshot, UInt64) -> Void
    ) {
        self.init(
            sampleRate: sampleRate,
            generation: generation,
            pollInterval: .nanoseconds(16_666_667),
            deliver: deliver
        )
    }

    init?(
        sampleRate: Double,
        generation: UInt64,
        pollInterval: DispatchTimeInterval,
        deliver: @escaping @Sendable (SpectrumSnapshot, UInt64) -> Void
    ) {
        guard let fft = SpectrumFFT(sampleRate: sampleRate),
              let stopped = rt_atomic_u8_create(0) else {
            return nil
        }
        guard rt_atomic_u8_is_lock_free(stopped) else {
            rt_atomic_u8_destroy(stopped)
            return nil
        }
        guard let mailbox = SpectrumMailbox() else {
            rt_atomic_u8_destroy(stopped)
            return nil
        }
        let queue = DispatchQueue(
            label: "com.mishandled.sculptor.spectrum-analysis",
            qos: .utility
        )
        let timer = DispatchSource.makeTimerSource(queue: queue)

        self.fft = fft
        self.mailbox = mailbox
        self.queue = queue
        self.timer = timer
        self.generation = generation
        self.deliver = deliver
        self.stopped = stopped
        submission = SpectrumSubmission(
            context: mailbox.opaqueContext,
            function: SpectrumMailbox.submit
        )

        timer.setEventHandler { [weak self] in
            self?.pollLatestFrame()
        }
        timer.schedule(
            deadline: .now() + pollInterval,
            repeating: pollInterval,
            leeway: .milliseconds(2)
        )
        timer.activate()
    }

    deinit {
        shutdown()
        rt_atomic_u8_destroy(stopped)
    }

    func shutdown() {
        let wasStopped = rt_atomic_u8_exchange_acq_rel(stopped, 1)
        guard wasStopped == 0 else { return }
        dispatchPrecondition(condition: .notOnQueue(queue))
        timer.cancel()
        queue.sync {}
    }

    private func pollLatestFrame() {
        guard rt_atomic_u8_load_acquire(stopped) == 0,
              let frame = mailbox.claimLatest() else {
            return
        }
        let snapshot = fft.analyze(frame.samples)
        mailbox.release(frame)
        guard rt_atomic_u8_load_acquire(stopped) == 0 else { return }
        deliver(snapshot, generation)
    }
}
```

The tap will capture only the immutable `SpectrumSubmission`. The timer is active before `SpectrumAnalyzer.init` returns, so `NoiseEngine` cannot install a tap before the consumer exists. `shutdown()` cancels then synchronously joins the serial queue; `NoiseEngine` must remove the tap before calling it.

- [ ] **Step 4: Run mailbox plus analyzer tests to verify GREEN**

```bash
cd Packages/AudioEngine
xcodebuild test \
  -scheme AudioEngine \
  -destination "platform=iOS Simulator,name=${SIM:-iPhone 16}" \
  -only-testing:AudioEngineTests/SpectrumMailboxTests \
  -only-testing:AudioEngineTests/SpectrumAnalyzerTests \
  > /tmp/spectrum-pipeline-green.log 2>&1
```

Expected: both suites pass with one delivery per newest complete frame and no delivery after shutdown returns.

- [ ] **Step 5: Commit the worker**

```bash
git add \
  Packages/AudioEngine/Sources/AudioEngine/SpectrumAnalyzer.swift \
  Packages/AudioEngine/Tests/AudioEngineTests/SpectrumAnalyzerTests.swift
git commit -m "feat(audio): add polling spectrum analyzer"
```

---

### Task 5: Actor-Isolated NoiseEngine Spectrum Lifecycle

**Files:**

- Modify: `Packages/AudioEngine/Sources/AudioEngine/NoiseEngine.swift:6-325`
- Delete: `Packages/AudioEngine/Tests/AudioEngineTests/NoiseEngineScopeTapTests.swift`
- Create: `Packages/AudioEngine/Tests/AudioEngineTests/NoiseEngineSpectrumTapTests.swift`
- Modify: `Packages/AudioEngine/Tests/AudioEngineTests/NoiseEngineMediaResetTests.swift`
- Modify: `Packages/AudioEngine/Tests/AudioEngineTests/NoiseEngineInterruptionTests.swift`
- Modify: `Packages/AudioEngine/Tests/AudioEngineTests/NoiseEngineSessionTests.swift`
- Modify: `Packages/AudioEngine/Tests/AudioEngineTests/FadeTests.swift`
- Modify: `Packages/AudioEngine/Tests/AudioEngineTests/NoiseEngineFormatTests.swift`
- Modify: `Packages/AudioEngine/Tests/AudioEngineTests/NoiseEngineTests.swift`
- Modify: `Packages/AudioEngine/Tests/AudioEngineTests/NoisePresetTests.swift`

**Interfaces:**

- Consumes: `SpectrumAnalyzerFactory`, `SpectrumAnalyzing`, `SpectrumSubmission`, and `SpectrumSnapshot` from Tasks 1–4.
- Produces: `NoiseEngine.onSpectrumSnapshot`, `spectrumAnalysisEnabled`, `isSpectrumTapInstalled`, `_installSpectrumTap()`, `_removeSpectrumTap()`, `_acceptSpectrumSnapshot(_:generation:)`, and the injected internal initializer.
- Preserves: public synthesis, gain, fade, audio-session, Now Playing callback, and fixed graph-format behavior.

- [ ] **Step 1: Replace the scope lifecycle suite with spectrum test doubles and tests**

Delete `NoiseEngineScopeTapTests.swift`. Create `Packages/AudioEngine/Tests/AudioEngineTests/NoiseEngineSpectrumTapTests.swift`:

```swift
import Foundation
import Testing
@testable import AudioEngine

final class StubSpectrumAnalyzer: SpectrumAnalyzing, @unchecked Sendable {
    let submission: SpectrumSubmission
    private let context: UnsafeMutableRawPointer
    private(set) var shutdownCount = 0

    init(submitSucceeds: Bool) {
        context = .allocate(byteCount: 1, alignment: 1)
        context.storeBytes(of: submitSucceeds, as: Bool.self)
        submission = SpectrumSubmission(
            context: context,
            function: { context, _, _ in
                context.load(as: Bool.self)
            }
        )
    }

    deinit {
        context.deallocate()
    }

    func shutdown() {
        shutdownCount += 1
    }
}

@MainActor
final class SpectrumAnalyzerFactorySpy {
    var setupFails = false
    var submitSucceeds = true
    private(set) var sampleRates: [Double] = []
    private(set) var generations: [UInt64] = []
    private(set) var analyzers: [StubSpectrumAnalyzer] = []
    private(set) var deliveries: [
        @Sendable (SpectrumSnapshot, UInt64) -> Void
    ] = []

    var factory: SpectrumAnalyzerFactory {
        { [weak self] sampleRate, generation, deliver in
            guard let self else { return nil }
            sampleRates.append(sampleRate)
            generations.append(generation)
            guard !setupFails else { return nil }

            let analyzer = StubSpectrumAnalyzer(
                submitSucceeds: submitSucceeds
            )
            analyzers.append(analyzer)
            deliveries.append(deliver)
            return analyzer
        }
    }

    func complete(
        _ snapshot: SpectrumSnapshot,
        deliveryIndex: Int
    ) {
        deliveries[deliveryIndex](
            snapshot,
            generations[deliveryIndex]
        )
    }
}

@MainActor
@Suite("NoiseEngine spectrum tap")
struct NoiseEngineSpectrumTapTests {
    @Test func installAndRemoveAreIdempotent() {
        let spy = SpectrumAnalyzerFactorySpy()
        let engine = makeEngine(spy)
        engine._setPlayingForTesting(true)

        engine._installSpectrumTap()
        #expect(engine.isSpectrumTapInstalled)
        #expect(spy.analyzers.count == 1)

        engine._installSpectrumTap()
        #expect(spy.analyzers.count == 1)

        engine._removeSpectrumTap()
        #expect(!engine.isSpectrumTapInstalled)
        #expect(spy.analyzers[0].shutdownCount == 1)

        engine._removeSpectrumTap()
        #expect(spy.analyzers[0].shutdownCount == 1)
    }

    @Test func enablementRespectsPlaybackState() {
        let stoppedSpy = SpectrumAnalyzerFactorySpy()
        let stopped = makeEngine(stoppedSpy)
        stopped.spectrumAnalysisEnabled = false
        stopped.spectrumAnalysisEnabled = true
        #expect(!stopped.isSpectrumTapInstalled)
        #expect(stoppedSpy.analyzers.isEmpty)

        let playingSpy = SpectrumAnalyzerFactorySpy()
        let playing = makeEngine(playingSpy)
        playing._setPlayingForTesting(true)
        playing._installSpectrumTap()
        playing.spectrumAnalysisEnabled = false
        #expect(!playing.isSpectrumTapInstalled)
        #expect(playingSpy.analyzers[0].shutdownCount == 1)
    }

    @Test func stoppingRemovesTapAndJoinsAnalyzer() {
        let spy = SpectrumAnalyzerFactorySpy()
        let engine = makeEngine(spy)
        engine._setPlayingForTesting(true)
        engine._installSpectrumTap()

        engine.stop()

        #expect(!engine.isPlaying)
        #expect(!engine.isSpectrumTapInstalled)
        #expect(spy.analyzers[0].shutdownCount == 1)
    }

    @Test func setupAndSubmissionFailuresAreNonFatal() throws {
        let setupSpy = SpectrumAnalyzerFactorySpy()
        setupSpy.setupFails = true
        let setupEngine = makeEngine(setupSpy)
        setupEngine._setPlayingForTesting(true)
        setupEngine.setGain(band: 2, dB: 5)
        setupEngine.masterVolume = 0.4
        var setupPlaybackChanges = 0
        setupEngine.onPlaybackStateChange = { _ in
            setupPlaybackChanges += 1
        }
        setupEngine._installSpectrumTap()
        #expect(setupEngine.isPlaying)
        #expect(!setupEngine.isSpectrumTapInstalled)
        #expect(setupEngine.bandCount == 8)
        #expect(setupEngine.gain(band: 2) == 5)
        #expect(setupEngine.masterVolume == 0.4)
        #expect(setupPlaybackChanges == 0)

        let submitSpy = SpectrumAnalyzerFactorySpy()
        submitSpy.submitSucceeds = false
        let submitEngine = makeEngine(submitSpy)
        submitEngine._setPlayingForTesting(true)
        var submitPlaybackChanges = 0
        var submitSpectrumChanges = 0
        submitEngine.onPlaybackStateChange = { _ in
            submitPlaybackChanges += 1
        }
        submitEngine.onSpectrumSnapshot = { _ in
            submitSpectrumChanges += 1
        }
        submitEngine._installSpectrumTap()
        let analyzer = try #require(submitSpy.analyzers.first)
        let samples = [Float](repeating: 0, count: SpectrumFFT.sampleCount)
        let accepted = samples.withUnsafeBufferPointer { buffer in
            analyzer.submission.submit(
                buffer.baseAddress!,
                count: buffer.count
            )
        }
        #expect(!accepted)
        #expect(submitEngine.isPlaying)
        #expect(submitEngine.isSpectrumTapInstalled)
        #expect(submitEngine.bandCount == 8)
        #expect(submitPlaybackChanges == 0)
        #expect(submitSpectrumChanges == 0)
        submitEngine._removeSpectrumTap()
    }

    @Test func deliveryRequiresCurrentActiveGeneration() async {
        let spy = SpectrumAnalyzerFactorySpy()
        let engine = makeEngine(spy)
        var received: [SpectrumSnapshot] = []
        engine.onSpectrumSnapshot = { received.append($0) }
        engine._setPlayingForTesting(true)
        engine._installSpectrumTap()

        let first = SpectrumSnapshot(
            bands: SIMD8<Float>(repeating: 0.5),
            rms: 0.4,
            peak: 0.3
        )
        spy.complete(first, deliveryIndex: 0)
        for _ in 0..<20 where received.isEmpty { await Task.yield() }
        #expect(received == [first])

        engine._removeSpectrumTap()
        spy.complete(.zero, deliveryIndex: 0)
        for _ in 0..<20 { await Task.yield() }
        #expect(received == [first])
    }

    @Test func deliveryWhileStoppedOrDisabledIsDiscarded() async {
        let spy = SpectrumAnalyzerFactorySpy()
        let engine = makeEngine(spy)
        var deliveryCount = 0
        engine.onSpectrumSnapshot = { _ in deliveryCount += 1 }
        engine._setPlayingForTesting(true)
        engine._installSpectrumTap()

        engine._setPlayingForTesting(false)
        spy.complete(.zero, deliveryIndex: 0)
        for _ in 0..<10 { await Task.yield() }
        #expect(deliveryCount == 0)

        engine._setPlayingForTesting(true)
        engine.spectrumAnalysisEnabled = false
        spy.complete(.zero, deliveryIndex: 0)
        for _ in 0..<10 { await Task.yield() }
        #expect(deliveryCount == 0)
    }

    @Test func reinstallUsesIncreasingGenerationAndEQSampleRate() {
        let spy = SpectrumAnalyzerFactorySpy()
        let engine = makeEngine(spy)
        engine._setPlayingForTesting(true)
        engine._installSpectrumTap()
        let firstGeneration = engine._spectrumGeneration
        engine._removeSpectrumTap()
        engine._installSpectrumTap()

        #expect(engine._spectrumGeneration > firstGeneration)
        #expect(spy.sampleRates == [44_100, 44_100])
        engine._removeSpectrumTap()
    }

    private func makeEngine(
        _ spy: SpectrumAnalyzerFactorySpy
    ) -> NoiseEngine {
        NoiseEngine(
            analyzerFactory: spy.factory,
            notificationCenter: NotificationCenter()
        )
    }
}
```

- [ ] **Step 2: Replace media-reset coverage with generation and rebuilt-format coverage**

Replace `Packages/AudioEngine/Tests/AudioEngineTests/NoiseEngineMediaResetTests.swift` with:

```swift
import AVFoundation
import Foundation
import Testing
@testable import AudioEngine

@MainActor
@Suite("Media services reset recovery")
struct NoiseEngineMediaResetTests {
    @Test func rebuildPreservesGainsGlobalAndBandCount() {
        let engine = NoiseEngine()
        engine.setGain(band: 2, dB: 5)
        engine.setGlobalGain(3)
        engine._recoverFromMediaServicesReset()
        #expect(engine.bandCount == 8)
        #expect(engine.gain(band: 2) == 5)
        #expect(abs(engine.globalGain - 3) < 0.001)
        #expect(!engine.isPlaying)
    }

    @Test func rebuildInvalidatesAnalyzerAndUsesRebuiltFormat() {
        let spy = SpectrumAnalyzerFactorySpy()
        let engine = NoiseEngine(
            analyzerFactory: spy.factory,
            notificationCenter: NotificationCenter()
        )
        engine._setPlayingForTesting(true)
        engine._installSpectrumTap()
        let firstGeneration = engine._spectrumGeneration
        engine._setPlayingForTesting(false)

        engine._recoverFromMediaServicesReset()
        #expect(!engine.isSpectrumTapInstalled)
        #expect(spy.analyzers[0].shutdownCount == 1)

        engine._setPlayingForTesting(true)
        engine._installSpectrumTap()
        #expect(engine._spectrumGeneration > firstGeneration)
        #expect(spy.sampleRates == [44_100, 44_100])
        engine._removeSpectrumTap()
    }

    @Test func resetNotificationHopsToMainActor() async {
        let center = NotificationCenter()
        let engine = NoiseEngine(notificationCenter: center)
        engine.isFading = true

        await Task.detached {
            center.post(
                name: AVAudioSession.mediaServicesWereResetNotification,
                object: nil
            )
        }.value
        for _ in 0..<20 where engine.isFading { await Task.yield() }
        #expect(!engine.isFading)
    }
}
```

- [ ] **Step 3: Add notification-thread isolation regressions**

Add `@MainActor` before the existing suites in `NoiseEngineInterruptionTests.swift` and `NoiseEngineSessionTests.swift`. Append this interruption test inside `NoiseEngineInterruptionTests`:

```swift
@Test func interruptionNotificationHopsToMainActor() async {
    let center = NotificationCenter()
    let engine = NoiseEngine(notificationCenter: center)
    engine._setPlayingForTesting(true)

    await Task.detached {
        center.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: [
                AVAudioSessionInterruptionTypeKey:
                    AVAudioSession.InterruptionType.began.rawValue
            ]
        )
    }.value
    for _ in 0..<20 where engine.isPlaying { await Task.yield() }
    #expect(!engine.isPlaying)
    #expect(engine._lastStopDeactivatedSession == false)
}
```

Append this route test inside `NoiseEngineSessionTests`:

```swift
@Test func routeNotificationHopsToMainActor() async {
    let center = NotificationCenter()
    let engine = NoiseEngine(notificationCenter: center)
    engine._setPlayingForTesting(true)

    await Task.detached {
        center.post(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: [
                AVAudioSessionRouteChangeReasonKey:
                    AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
            ]
        )
    }.value
    for _ in 0..<20 where engine.isPlaying { await Task.yield() }
    #expect(!engine.isPlaying)
    #expect(engine._lastStopDeactivatedSession == true)
}
```

- [ ] **Step 4: Run the lifecycle suites to verify RED**

```bash
cd Packages/AudioEngine
xcodebuild test \
  -scheme AudioEngine \
  -destination "platform=iOS Simulator,name=${SIM:-iPhone 16}" \
  -only-testing:AudioEngineTests/NoiseEngineSpectrumTapTests \
  -only-testing:AudioEngineTests/NoiseEngineMediaResetTests \
  -only-testing:AudioEngineTests/NoiseEngineInterruptionTests \
  -only-testing:AudioEngineTests/NoiseEngineSessionTests \
  > /tmp/noise-engine-spectrum-red.log 2>&1
status=$?
tail -80 /tmp/noise-engine-spectrum-red.log
exit $status
```

Expected: build failure because the spectrum APIs, factory initializer, and actor-isolated seams do not exist.

- [ ] **Step 5: Isolate NoiseEngine and replace its public scope state**

Add `@MainActor` immediately before `public final class NoiseEngine`. Replace the existing `isPlaying` callback block, scope callback/state, and `scopeEnabled` property with:

```swift
public private(set) var isPlaying = false {
    didSet {
        guard oldValue != isPlaying else { return }
        onPlaybackStateChange?(isPlaying)
    }
}

public var onPlaybackStateChange: (@MainActor @Sendable (Bool) -> Void)?
public var onSpectrumSnapshot:
    (@MainActor @Sendable (SpectrumSnapshot) -> Void)?

private var spectrumTapInstalled = false
private var spectrumAnalyzer: (any SpectrumAnalyzing)?
private var spectrumGeneration: UInt64 = 0
private static let spectrumBufferSize = AVAudioFrameCount(
    SpectrumFFT.sampleCount
)
private let analyzerFactory: SpectrumAnalyzerFactory
private let notificationCenter: NotificationCenter

public var spectrumAnalysisEnabled = true {
    didSet {
        guard spectrumAnalysisEnabled != oldValue else { return }
        if spectrumAnalysisEnabled {
            if isPlaying { _installSpectrumTap() }
        } else {
            _removeSpectrumTap()
        }
    }
}
```

The playback callback no longer dispatches from `didSet`: the entire class is main-actor isolated, so delivery is already on the documented executor.

- [ ] **Step 6: Replace scope tap helpers with generation-checked spectrum helpers**

Replace `isScopeTapInstalled`, `_installScopeTap()`, and `_removeScopeTap()` with:

```swift
var isSpectrumTapInstalled: Bool { spectrumTapInstalled }
var _spectrumGeneration: UInt64 { spectrumGeneration }

func _setPlayingForTesting(_ value: Bool) {
    isPlaying = value
}

func _installSpectrumTap() {
    guard !spectrumTapInstalled,
          spectrumAnalysisEnabled,
          isPlaying else {
        return
    }

    spectrumGeneration &+= 1
    let installationGeneration = spectrumGeneration
    let sampleRate = eq.outputFormat(forBus: 0).sampleRate
    guard let analyzer = analyzerFactory(
        sampleRate,
        installationGeneration,
        { [weak self] snapshot, completedGeneration in
            Task { @MainActor [weak self] in
                self?._acceptSpectrumSnapshot(
                    snapshot,
                    generation: completedGeneration
                )
            }
        }
    ) else {
        return
    }

    let submission = analyzer.submission
    spectrumAnalyzer = analyzer
    eq.installTap(
        onBus: 0,
        bufferSize: Self.spectrumBufferSize,
        format: nil
    ) { buffer, _ in
        guard let channel = buffer.floatChannelData?[0] else { return }
        _ = submission.submit(channel, count: Int(buffer.frameLength))
    }
    spectrumTapInstalled = true
}

func _removeSpectrumTap() {
    guard spectrumTapInstalled || spectrumAnalyzer != nil else { return }
    if spectrumTapInstalled {
        eq.removeTap(onBus: 0)
        spectrumTapInstalled = false
    }
    spectrumGeneration &+= 1
    let analyzer = spectrumAnalyzer
    spectrumAnalyzer = nil
    analyzer?.shutdown()
}

func _acceptSpectrumSnapshot(
    _ snapshot: SpectrumSnapshot,
    generation: UInt64
) {
    guard generation == spectrumGeneration,
          isPlaying,
          spectrumAnalysisEnabled else {
        return
    }
    onSpectrumSnapshot?(snapshot)
}

private func discardSpectrumPipelineAfterGraphLoss() {
    spectrumTapInstalled = false
    spectrumGeneration &+= 1
    let analyzer = spectrumAnalyzer
    spectrumAnalyzer = nil
    analyzer?.shutdown()
}
```

The render block captures only `SpectrumSubmission`, whose raw context remains alive because `NoiseEngine` retains the analyzer until after the tap is removed and the worker is joined.

- [ ] **Step 7: Replace initialization and teardown**

Replace `public init()` and `deinit` with:

```swift
public convenience init() {
    self.init(
        analyzerFactory: { sampleRate, generation, deliver in
            SpectrumAnalyzer(
                sampleRate: sampleRate,
                generation: generation,
                deliver: deliver
            )
        },
        notificationCenter: .default
    )
}

convenience init(notificationCenter: NotificationCenter) {
    self.init(
        analyzerFactory: { sampleRate, generation, deliver in
            SpectrumAnalyzer(
                sampleRate: sampleRate,
                generation: generation,
                deliver: deliver
            )
        },
        notificationCenter: notificationCenter
    )
}

init(
    analyzerFactory: @escaping SpectrumAnalyzerFactory,
    notificationCenter: NotificationCenter
) {
    self.analyzerFactory = analyzerFactory
    self.notificationCenter = notificationCenter
    eq = Self.makeEQ()
    stateL.initialize(to: NoiseSource(seed: 0x1234_5678_9ABC_DEF0))
    stateR.initialize(to: NoiseSource(seed: 0x0FED_CBA9_8765_4321))
    buildGraph()

    notificationCenter.addObserver(
        self,
        selector: #selector(handleInterruption(_:)),
        name: AVAudioSession.interruptionNotification,
        object: nil
    )
    notificationCenter.addObserver(
        self,
        selector: #selector(handleRouteChange(_:)),
        name: AVAudioSession.routeChangeNotification,
        object: nil
    )
    notificationCenter.addObserver(
        self,
        selector: #selector(handleMediaServicesReset(_:)),
        name: AVAudioSession.mediaServicesWereResetNotification,
        object: nil
    )
}

deinit {
    fadeTask?.cancel()
    if spectrumTapInstalled { eq.removeTap(onBus: 0) }
    spectrumGeneration &+= 1
    spectrumAnalyzer?.shutdown()
    engine.stop()
    notificationCenter.removeObserver(self)
    stateL.deinitialize(count: 1)
    stateL.deallocate()
    stateR.deinitialize(count: 1)
    stateR.deallocate()
}
```

- [ ] **Step 8: Replace start, stop, fade, and media reset lifecycle methods**

Replace the complete `start()` and both `stop` methods with:

```swift
public func start() throws {
    fadeTask?.cancel()
    fadeTask = nil
    isFading = false
    engine.mainMixerNode.outputVolume = masterVolume
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playback, mode: .default)
    try session.setActive(true)
    if !engine.isRunning { try engine.start() }
    isPlaying = true
    if spectrumAnalysisEnabled { _installSpectrumTap() }
}

public func stop(deactivateSession: Bool = true) {
    fadeTask?.cancel()
    fadeTask = nil
    isFading = false
    _removeSpectrumTap()
    finishStop(deactivateSession: deactivateSession)
    isPlaying = false
}

public func stop(
    fadeDuration: TimeInterval,
    deactivateSession: Bool = true
) {
    guard fadeDuration > 0, isPlaying else {
        stop(deactivateSession: deactivateSession)
        return
    }
    fadeTask?.cancel()
    _removeSpectrumTap()
    isPlaying = false
    let steps = Self.fadeStepCount(for: fadeDuration)
    let curve = Fade.curve(
        from: engine.mainMixerNode.outputVolume,
        steps: steps
    )
    isFading = true
    fadeTask = Task { @MainActor [weak self] in
        for value in curve {
            try? await Task.sleep(for: .seconds(Self.fadeStepInterval))
            guard let self, !Task.isCancelled else { return }
            self.engine.mainMixerNode.outputVolume = value
        }
        guard let self, !Task.isCancelled else { return }
        self.isFading = false
        self.finishStop(deactivateSession: deactivateSession)
    }
}
```

Replace `_recoverFromMediaServicesReset()` with:

```swift
func _recoverFromMediaServicesReset() {
    let bandGains = eq.bands.map(\.gain)
    let global = eq.globalGain
    let wasPlaying = isPlaying
    fadeTask?.cancel()
    fadeTask = nil
    isFading = false

    // The old graph is already invalid; do not message its EQ node.
    discardSpectrumPipelineAfterGraphLoss()
    engine = AVAudioEngine()
    eq = Self.makeEQ()
    buildGraph()
    for (index, gain) in bandGains.enumerated() {
        eq.bands[index].gain = gain
    }
    eq.globalGain = global
    isPlaying = false
    if wasPlaying { try? start() }
}
```

- [ ] **Step 9: Make notification selectors parse then hop to main**

Replace the three selector methods with:

```swift
@objc nonisolated private func handleInterruption(
    _ note: Notification
) {
    guard let rawType = note.userInfo?[
        AVAudioSessionInterruptionTypeKey
    ] as? UInt else { return }
    let rawOptions = note.userInfo?[
        AVAudioSessionInterruptionOptionKey
    ] as? UInt ?? 0

    Task { @MainActor [weak self] in
        guard let type = AVAudioSession.InterruptionType(
            rawValue: rawType
        ) else { return }
        self?._applyInterruption(
            type: type,
            options: AVAudioSession.InterruptionOptions(rawValue: rawOptions)
        )
    }
}

@objc nonisolated private func handleRouteChange(
    _ note: Notification
) {
    guard let rawReason = note.userInfo?[
        AVAudioSessionRouteChangeReasonKey
    ] as? UInt else { return }

    Task { @MainActor [weak self] in
        guard let reason = AVAudioSession.RouteChangeReason(
            rawValue: rawReason
        ) else { return }
        if AudioSessionPolicy.routeChangeAction(reason: reason) == .pause {
            self?.stop()
        }
    }
}

@objc nonisolated private func handleMediaServicesReset(
    _ note: Notification
) {
    Task { @MainActor [weak self] in
        self?._recoverFromMediaServicesReset()
    }
}
```

Only `UInt` values cross the actor hop; `Notification` and `userInfo` do not.

- [ ] **Step 10: Apply the required test actor annotations**

Apply these exact annotation changes to the existing suite declarations:

```diff
+@MainActor
@Suite("Fade curve")
struct FadeTests

+@MainActor
@Suite("NoiseEngine interruption resume wiring")
struct NoiseEngineInterruptionTests

+@MainActor
@Suite("Session deactivation policy")
struct NoiseEngineSessionTests
```

Add the annotation immediately above these exact top-level declarations; their test bodies do not change:

```diff
// NoiseEngineFormatTests.swift
+@MainActor
@Test func usesExplicitStereo44kFormat()

// NoiseEngineTests.swift
+@MainActor
@Test func hasEightBandsAtExpectedFrequencies()

+@MainActor
@Test func setGainClampsToRange()

+@MainActor
@Test func applyPresetSetsAllBands()

+@MainActor
@Test func masterVolumeClampsAndDrivesMixer()

// NoisePresetTests.swift — all pure preset tests remain nonisolated.
+@MainActor
@Test func applySetsGlobalGainFromPreset()
```

The media-reset and renamed spectrum suites already carry suite-level isolation in Steps 1–2.

- [ ] **Step 11: Run lifecycle and full-package tests to verify GREEN**

```bash
cd Packages/AudioEngine
xcodebuild test \
  -scheme AudioEngine \
  -destination "platform=iOS Simulator,name=${SIM:-iPhone 16}" \
  -only-testing:AudioEngineTests/NoiseEngineSpectrumTapTests \
  -only-testing:AudioEngineTests/NoiseEngineMediaResetTests \
  -only-testing:AudioEngineTests/NoiseEngineInterruptionTests \
  -only-testing:AudioEngineTests/NoiseEngineSessionTests \
  > /tmp/noise-engine-spectrum-green.log 2>&1

xcodebuild test \
  -scheme AudioEngine \
  -destination "platform=iOS Simulator,name=${SIM:-iPhone 16}" \
  > /tmp/audioengine-spectrum-full.log 2>&1
```

Expected: focused lifecycle suites and the complete AudioEngine suite succeed; analyzer setup/submission failure leaves `isPlaying` untouched, reset invalidates the old generation, and background notifications mutate control state only after the main-actor hop.

- [ ] **Step 12: Commit the engine integration**

```bash
git add \
  Packages/AudioEngine/Sources/AudioEngine/NoiseEngine.swift \
  Packages/AudioEngine/Tests/AudioEngineTests/NoiseEngineSpectrumTapTests.swift \
  Packages/AudioEngine/Tests/AudioEngineTests/NoiseEngineMediaResetTests.swift \
  Packages/AudioEngine/Tests/AudioEngineTests/NoiseEngineInterruptionTests.swift \
  Packages/AudioEngine/Tests/AudioEngineTests/NoiseEngineSessionTests.swift \
  Packages/AudioEngine/Tests/AudioEngineTests/FadeTests.swift \
  Packages/AudioEngine/Tests/AudioEngineTests/NoiseEngineFormatTests.swift \
  Packages/AudioEngine/Tests/AudioEngineTests/NoiseEngineTests.swift \
  Packages/AudioEngine/Tests/AudioEngineTests/NoisePresetTests.swift
git add -u \
  Packages/AudioEngine/Tests/AudioEngineTests/NoiseEngineScopeTapTests.swift
git commit -m "refactor(audio): replace scope tap with spectrum"
```

---

### Task 6: Playback Spectrum State and Home Visibility Policy

**Files:**

- Modify: `Sculptor/Sources/PlaybackViewModel.swift:13-30,49-62,100-116,240-249`
- Create: `Sculptor/Sources/VisualizationPolicy.swift`
- Modify: `Sculptor/Sources/RootView.swift:4-27`
- Modify: `Sculptor/Sources/HomeView.swift:91-117`
- Modify: `Sculptor/Tests/PlaybackViewModelTests.swift:96-100`
- Create: `Sculptor/Tests/VisualizationPolicyTests.swift`

**Interfaces:**

- Consumes: `NoiseEngine.onSpectrumSnapshot`, `NoiseEngine.spectrumAnalysisEnabled`, and `SpectrumSnapshot` from Task 5.
- Produces: `PlaybackViewModel.spectrumSnapshot`, `spectrumReceivedAt`, `visualizationActive`, `_applyPlaybackState(_:)`, `_ingestSpectrumSnapshot(_:at:)`, `setVisualizationActive(_:)`, and `VisualizationPolicy.isActive(sceneIsActive:presetsPresented:)`.

- [ ] **Step 1: Replace the obsolete scope test and add spectrum/lifecycle tests**

Delete `ingestScopeSamplesIgnoredWhenPaused` from `PlaybackViewModelTests.swift` and add these tests inside the existing `@MainActor` suite:

```swift
@Test func spectrumCallbackIsIgnoredWhilePaused() {
    let engine = NoiseEngine()
    let vm = PlaybackViewModel(engine: engine, defaults: freshDefaults())
    let snapshot = SpectrumSnapshot(
        bands: SIMD8<Float>(repeating: 0.5),
        rms: 0.5,
        peak: 0.5
    )

    vm.setVisualizationActive(true)
    engine.onSpectrumSnapshot?(snapshot)

    #expect(vm.spectrumSnapshot == .zero)
    #expect(vm.spectrumReceivedAt == nil)
}

@Test func spectrumCallbackIsAcceptedWhilePlayingAndVisible() {
    let engine = NoiseEngine()
    let vm = PlaybackViewModel(engine: engine, defaults: freshDefaults())
    let snapshot = SpectrumSnapshot(
        bands: SIMD8<Float>(repeating: 0.5),
        rms: 0.5,
        peak: 0.75
    )

    vm.setVisualizationActive(true)
    engine.onPlaybackStateChange?(true)
    engine.onSpectrumSnapshot?(snapshot)

    #expect(vm.spectrumSnapshot == snapshot)
    #expect(vm.spectrumReceivedAt != nil)
}

@Test func spectrumCallbackIsIgnoredWhileVisualizationInactive() {
    let engine = NoiseEngine()
    let vm = PlaybackViewModel(engine: engine, defaults: freshDefaults())
    let snapshot = SpectrumSnapshot(
        bands: SIMD8<Float>(repeating: 0.8),
        rms: 0.8,
        peak: 0.8
    )

    engine.onPlaybackStateChange?(true)
    engine.onSpectrumSnapshot?(snapshot)

    #expect(vm.spectrumSnapshot == .zero)
    #expect(vm.spectrumReceivedAt == nil)
}

@Test func inactiveVisualizationClearsTargetAndDisablesAnalysis() {
    let engine = NoiseEngine()
    let vm = PlaybackViewModel(engine: engine, defaults: freshDefaults())
    let now = ContinuousClock().now
    let snapshot = SpectrumSnapshot(
        bands: SIMD8<Float>(repeating: 0.8),
        rms: 0.8,
        peak: 0.8
    )

    vm.setVisualizationActive(true)
    vm._applyPlaybackState(true)
    vm._ingestSpectrumSnapshot(snapshot, at: now)
    vm.setVisualizationActive(false)

    #expect(!vm.visualizationActive)
    #expect(vm.spectrumSnapshot == .zero)
    #expect(vm.spectrumReceivedAt == nil)
    #expect(!engine.spectrumAnalysisEnabled)
}

@Test func activeVisualizationReenablesAnalysis() {
    let engine = NoiseEngine()
    let vm = PlaybackViewModel(engine: engine, defaults: freshDefaults())
    #expect(!engine.spectrumAnalysisEnabled)

    vm.setVisualizationActive(true)

    #expect(vm.visualizationActive)
    #expect(engine.spectrumAnalysisEnabled)
}

@Test func playbackStopClearsSpectrumTarget() {
    let vm = PlaybackViewModel(defaults: freshDefaults())
    let now = ContinuousClock().now
    let snapshot = SpectrumSnapshot(
        bands: SIMD8<Float>(repeating: 1),
        rms: 1,
        peak: 1
    )

    vm.setVisualizationActive(true)
    vm._applyPlaybackState(true)
    vm._ingestSpectrumSnapshot(snapshot, at: now)
    vm._applyPlaybackState(false)

    #expect(vm.spectrumSnapshot == .zero)
    #expect(vm.spectrumReceivedAt == nil)
}

@Test func missingSpectrumUpdatesPreservePlaybackTimerAndNowPlaying() {
    let engine = NoiseEngine()
    let vm = PlaybackViewModel(engine: engine, defaults: freshDefaults())
    vm.nowPlayingTitle = "Failure fallback"
    vm.setVisualizationActive(true)
    engine.onPlaybackStateChange?(true)
    vm.startSleepTimer(minutes: 30)
    vm._sleepTick(now: Date().addingTimeInterval(1))

    #expect(vm.isPlaying)
    #expect(vm.spectrumSnapshot == .zero)
    #expect(vm.sleepMinutes == 30)
    #expect((vm.sleepRemaining ?? 0) > 29 * 60)
    let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
    #expect(info?[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 1)
    vm.cancelSleepTimer()
}
```

Create `Sculptor/Tests/VisualizationPolicyTests.swift`:

```swift
import Testing
@testable import Sculptor

@Suite("Visualization visibility policy")
struct VisualizationPolicyTests {
    @Test func activeHomeEnablesVisualization() {
        #expect(
            VisualizationPolicy.isActive(
                sceneIsActive: true,
                presetsPresented: false
            )
        )
    }

    @Test func sculptPresentationLeavesVisualizationActive() {
        // Sculpt is deliberately absent from this policy.
        #expect(
            VisualizationPolicy.isActive(
                sceneIsActive: true,
                presetsPresented: false
            )
        )
    }

    @Test func presetsPresentationDisablesVisualization() {
        #expect(
            !VisualizationPolicy.isActive(
                sceneIsActive: true,
                presetsPresented: true
            )
        )
    }

    @Test func inactiveSceneDisablesVisualization() {
        #expect(
            !VisualizationPolicy.isActive(
                sceneIsActive: false,
                presetsPresented: false
            )
        )
    }
}
```

- [ ] **Step 2: Regenerate and run focused tests to verify RED**

```bash
tuist generate --no-open
xcodebuild test \
  -workspace Sculptor.xcworkspace \
  -scheme Sculptor-Workspace \
  -destination "platform=iOS Simulator,name=${SIM:-iPhone 16}" \
  -only-testing:SculptorTests/PlaybackViewModelTests \
  -only-testing:SculptorTests/VisualizationPolicyTests \
  > /tmp/ripple-lifecycle-red.log 2>&1
status=$?
tail -80 /tmp/ripple-lifecycle-red.log
exit $status
```

Expected: build failure for the missing spectrum state and visibility policy.

- [ ] **Step 3: Add the pure visibility policy**

Create `Sculptor/Sources/VisualizationPolicy.swift`:

```swift
enum VisualizationPolicy {
    static func isActive(
        sceneIsActive: Bool,
        presetsPresented: Bool
    ) -> Bool {
        sceneIsActive && !presetsPresented
    }
}
```

- [ ] **Step 4: Replace PlaybackViewModel scope plumbing**

Replace `scopeSamples` with:

```swift
@Published private(set) var spectrumSnapshot = SpectrumSnapshot.zero
@Published private(set) var spectrumReceivedAt: ContinuousClock.Instant?
@Published private(set) var visualizationActive = false
```

Add beside the other private properties:

```swift
private let clock = ContinuousClock()
```

Replace the two engine callback assignments in `init` with:

```swift
engine.spectrumAnalysisEnabled = false
engine.onPlaybackStateChange = { [weak self] playing in
    self?._applyPlaybackState(playing)
}
engine.onSpectrumSnapshot = { [weak self] snapshot in
    guard let self else { return }
    self._ingestSpectrumSnapshot(snapshot, at: self.clock.now)
}
```

Replace `togglePlay()` and `stopPlayback(fade:)` with:

```swift
func togglePlay() {
    if isPlaying {
        stopPlayback()
        cancelSleepTimer()
    } else {
        errorText = nil
        do {
            try engine.start()
        } catch {
            errorText = error.localizedDescription
        }
        _applyPlaybackState(engine.isPlaying)
    }
}

private func stopPlayback(fade: TimeInterval = 0.15) {
    engine.stop(fadeDuration: fade)
    _applyPlaybackState(engine.isPlaying)
}
```

Replace `_ingestScopeSamples(_:)` and `setScopeActive(_:)` with:

```swift
func _applyPlaybackState(_ playing: Bool) {
    isPlaying = playing
    if !playing { clearSpectrumTarget() }
}

func _ingestSpectrumSnapshot(
    _ snapshot: SpectrumSnapshot,
    at instant: ContinuousClock.Instant
) {
    guard isPlaying, visualizationActive else { return }
    spectrumSnapshot = snapshot
    spectrumReceivedAt = instant
}

func setVisualizationActive(_ active: Bool) {
    visualizationActive = active
    engine.spectrumAnalysisEnabled = active
    if !active { clearSpectrumTarget() }
}

private func clearSpectrumTarget() {
    spectrumSnapshot = .zero
    spectrumReceivedAt = nil
}
```

- [ ] **Step 5: Replace RootView scene-only scope policy**

Replace `Sculptor/Sources/RootView.swift` with:

```swift
import SwiftUI
import DesignSystem

struct RootView: View {
    @StateObject private var vm = PlaybackViewModel()
    @State private var showSculpt = false
    @State private var showPresets = false
    @Environment(\.scenePhase) private var scenePhase

    private var visualizationActive: Bool {
        VisualizationPolicy.isActive(
            sceneIsActive: scenePhase == .active,
            presetsPresented: showPresets
        )
    }

    var body: some View {
        HomeView(
            vm: vm,
            onOpenSculpt: { showSculpt = true },
            onOpenPresets: { showPresets = true }
        )
        .sheet(isPresented: $showSculpt, onDismiss: {
            if vm.presetToRename != nil { showPresets = true }
        }) {
            SculptSheet(vm: vm)
        }
        .fullScreenCover(isPresented: $showPresets) {
            PresetsView(vm: vm)
        }
        .onChange(of: visualizationActive, initial: true) { _, active in
            vm.setVisualizationActive(active)
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: CustomPreset.self, inMemory: true)
}
```

The policy intentionally omits `showSculpt`, preserving rendering in the uncovered area around the opaque sheet.

- [ ] **Step 6: Remove Home's now-unbacked scope region**

Replace `HomeView.heroCenter` with this layout. It removes both the 80-point scope and the extra knob-row top padding; Task 9 inserts the finished renderer behind the view.

```swift
private var heroCenter: some View {
    VStack(spacing: DockSpacing.lg) {
        PlayHeroButton(isPlaying: vm.isPlaying) {
            vm.togglePlay()
        }

        HStack(spacing: DockSpacing.xl * 2) {
            VolumeKnob(
                value: $vm.masterVolume,
                icon: "speaker.wave.2.fill",
                label: "NOISE"
            )
            VolumeKnob(
                value: Binding(
                    get: { systemVolume.level },
                    set: { systemVolume.setLevel($0) }
                ),
                icon: "iphone",
                label: "PHONE"
            )
        }
        .background(
            HiddenVolumeHost(volume: systemVolume)
                .frame(width: 1, height: 1)
        )

        Text(vm.isPlaying ? "Playing · tap to pause" : "Paused")
            .font(DockType.font(12))
            .foregroundStyle(DockColor.textTertiary)

        if let err = vm.errorText {
            Text(err)
                .font(DockType.font(12))
                .foregroundStyle(.red)
        }
    }
}
```

- [ ] **Step 7: Run focused tests to verify GREEN**

```bash
tuist generate --no-open
xcodebuild test \
  -workspace Sculptor.xcworkspace \
  -scheme Sculptor-Workspace \
  -destination "platform=iOS Simulator,name=${SIM:-iPhone 16}" \
  -only-testing:SculptorTests/PlaybackViewModelTests \
  -only-testing:SculptorTests/VisualizationPolicyTests \
  > /tmp/ripple-lifecycle-green.log 2>&1
```

Expected: both suites pass without starting `AVAudioSession`; initial Root appearance enables visualization, Presets disables it, and Sculpt does not affect it.

- [ ] **Step 8: Commit app spectrum state**

```bash
git add \
  Sculptor/Sources/PlaybackViewModel.swift \
  Sculptor/Sources/VisualizationPolicy.swift \
  Sculptor/Sources/RootView.swift \
  Sculptor/Sources/HomeView.swift \
  Sculptor/Tests/PlaybackViewModelTests.swift \
  Sculptor/Tests/VisualizationPolicyTests.swift
git commit -m "feat(app): wire spectrum lifecycle"
```

---

### Task 7: Deterministic Ripple Animation State

**Files:**

- Create: `Sculptor/Sources/RippleAnimationState.swift`
- Create: `Sculptor/Tests/RippleAnimationStateTests.swift`

**Interfaces:**

- Consumes: `SpectrumSnapshot.init(bands:rms:peak:)` and `.zero`.
- Produces: `RippleAnimationInput`, `RippleMotionProfile.resolve(reduceMotion:lowPowerMode:)`, `RippleUniforms`, `RippleAnimationState.init(at:)`, `retarget(to:at:)`, and nonmutating `uniforms(at:)`.

- [ ] **Step 1: Write explicit-clock envelope and uniform tests**

Create `Sculptor/Tests/RippleAnimationStateTests.swift`:

```swift
import AudioEngine
import Testing
@testable import Sculptor

@Suite("Ripple animation state")
struct RippleAnimationStateTests {
    private let clock = ContinuousClock()

    private func snapshot(_ value: Float) -> SpectrumSnapshot {
        SpectrumSnapshot(
            bands: SIMD8<Float>(repeating: value),
            rms: value,
            peak: value
        )
    }

    private func input(
        snapshot: SpectrumSnapshot,
        receivedAt: ContinuousClock.Instant?,
        isPlaying: Bool = true,
        masterVolume: Float = 1,
        isActive: Bool = true,
        reduceMotion: Bool = false,
        lowPowerMode: Bool = false
    ) -> RippleAnimationInput {
        RippleAnimationInput(
            snapshot: snapshot,
            receivedAt: receivedAt,
            isPlaying: isPlaying,
            masterVolume: masterVolume,
            isActive: isActive,
            reduceMotion: reduceMotion,
            lowPowerMode: lowPowerMode
        )
    }

    @Test func attackUses120MillisecondTimeConstant() {
        let start = clock.now
        var state = RippleAnimationState(at: start)
        state.retarget(
            to: input(snapshot: snapshot(1), receivedAt: start),
            at: start
        )
        let uniforms = state.uniforms(
            at: start.advanced(by: .milliseconds(120))
        )
        #expect(abs(uniforms.rms - 0.63212055) < 0.0001)
        #expect(abs(uniforms.peak - 0.63212055) < 0.0001)
    }

    @Test func releaseUses450MillisecondTimeConstant() {
        let start = clock.now
        let attackEnd = start.advanced(by: .milliseconds(120))
        var state = RippleAnimationState(at: start)
        state.retarget(
            to: input(snapshot: snapshot(1), receivedAt: start),
            at: start
        )
        let attacked = state.uniforms(at: attackEnd)
        state.retarget(
            to: input(
                snapshot: .zero,
                receivedAt: nil,
                isPlaying: false
            ),
            at: attackEnd
        )
        let released = state.uniforms(
            at: attackEnd.advanced(by: .milliseconds(450))
        )
        #expect(abs(released.rms - attacked.rms * 0.36787945) < 0.0001)
        #expect(
            abs(released.bandsLow.x - attacked.bandsLow.x * 0.36787945)
                < 0.0001
        )
        #expect(released.audioResponseScale == 1)
    }

    @Test func peakUses250MillisecondRelease() {
        let start = clock.now
        let attackEnd = start.advanced(by: .milliseconds(120))
        var state = RippleAnimationState(at: start)
        state.retarget(
            to: input(snapshot: snapshot(1), receivedAt: start),
            at: start
        )
        let attacked = state.uniforms(at: attackEnd)
        state.retarget(
            to: input(snapshot: .zero, receivedAt: attackEnd),
            at: attackEnd
        )
        let released = state.uniforms(
            at: attackEnd.advanced(by: .milliseconds(250))
        )
        #expect(abs(released.peak - attacked.peak * 0.36787945) < 0.0001)
    }

    @Test func retargetStartsFromCurrentDisplayedValue() {
        let start = clock.now
        let retargetTime = start.advanced(by: .milliseconds(60))
        var state = RippleAnimationState(at: start)
        state.retarget(
            to: input(snapshot: snapshot(1), receivedAt: start),
            at: start
        )
        let before = state.uniforms(at: retargetTime)
        state.retarget(
            to: input(snapshot: snapshot(0.1), receivedAt: retargetTime),
            at: retargetTime
        )
        let after = state.uniforms(at: retargetTime)
        #expect(abs(after.rms - before.rms) < 0.000001)
        #expect(abs(after.bandsLow.x - before.bandsLow.x) < 0.000001)
    }

    @Test func staleSpectrumReleasesAfter350Milliseconds() {
        let start = clock.now
        let staleBoundary = start.advanced(by: .milliseconds(350))
        var state = RippleAnimationState(at: start)
        state.retarget(
            to: input(snapshot: snapshot(1), receivedAt: start),
            at: start
        )
        let atBoundary = state.uniforms(at: staleBoundary)
        let released = state.uniforms(
            at: staleBoundary.advanced(by: .milliseconds(450))
        )
        #expect(abs(released.rms - atBoundary.rms * 0.36787945) < 0.0001)
    }

    @Test func freshSnapshotAfterStaleResumesAttack() {
        let start = clock.now
        let staleTime = start.advanced(by: .milliseconds(900))
        var state = RippleAnimationState(at: start)
        state.retarget(
            to: input(snapshot: snapshot(1), receivedAt: start),
            at: start
        )
        let stale = state.uniforms(at: staleTime)
        state.retarget(
            to: input(snapshot: snapshot(1), receivedAt: staleTime),
            at: staleTime
        )
        let resumed = state.uniforms(
            at: staleTime.advanced(by: .milliseconds(120))
        )
        #expect(resumed.rms > stale.rms)
    }

    @Test func masterVolumeOnlyScalesAudioContribution() {
        let start = clock.now
        var state = RippleAnimationState(at: start)
        state.retarget(
            to: input(
                snapshot: snapshot(1),
                receivedAt: start,
                masterVolume: 0.25
            ),
            at: start
        )
        let uniforms = state.uniforms(
            at: start.advanced(by: .milliseconds(120))
        )
        #expect(abs(uniforms.audioResponseScale - 0.25) < 0.0001)
        #expect(abs(uniforms.rms - 0.63212055) < 0.0001)
        #expect(abs(uniforms.elapsedTime - 0.12) < 0.0001)
    }

    @Test func pausedStatePreservesDriftWithZeroAudio() {
        let start = clock.now
        var state = RippleAnimationState(at: start)
        state.retarget(
            to: input(
                snapshot: snapshot(1),
                receivedAt: start,
                isPlaying: false
            ),
            at: start
        )
        let uniforms = state.uniforms(
            at: start.advanced(by: .seconds(1))
        )
        #expect(uniforms.bandsLow == .zero)
        #expect(uniforms.bandsHigh == .zero)
        #expect(uniforms.rms == 0)
        #expect(uniforms.peak == 0)
        #expect(uniforms.audioResponseScale == 1)
        #expect(abs(uniforms.elapsedTime - 1) < 0.0001)
    }

    @Test func inactiveStateFreezesShaderTimeWhileEnvelopeAges() {
        let start = clock.now
        let inactiveAt = start.advanced(by: .seconds(1))
        var state = RippleAnimationState(at: start)
        state.retarget(
            to: input(snapshot: snapshot(1), receivedAt: start),
            at: start
        )
        state.retarget(
            to: input(
                snapshot: .zero,
                receivedAt: nil,
                isActive: false
            ),
            at: inactiveAt
        )
        let uniforms = state.uniforms(
            at: inactiveAt.advanced(by: .seconds(10))
        )
        #expect(abs(uniforms.elapsedTime - 1) < 0.0001)
        #expect(uniforms.rms < 0.0001)
    }

    @Test func reducedProfilesUseThirtyFPSAndOneNoiseOctave() {
        let normal = RippleMotionProfile.resolve(
            reduceMotion: false,
            lowPowerMode: false
        )
        let lowPower = RippleMotionProfile.resolve(
            reduceMotion: false,
            lowPowerMode: true
        )
        let reduced = RippleMotionProfile.resolve(
            reduceMotion: true,
            lowPowerMode: false
        )
        #expect(abs(normal.minimumInterval - 1.0 / 60.0) < 0.000001)
        #expect(normal.detailScale == 1)
        #expect(abs(lowPower.minimumInterval - 1.0 / 30.0) < 0.000001)
        #expect(lowPower.detailScale == 0)
        #expect(lowPower.peakScale < normal.peakScale)
        #expect(abs(reduced.minimumInterval - 1.0 / 30.0) < 0.000001)
        #expect(reduced.detailScale == 0)
        #expect(reduced.peakScale == 0)
        #expect(reduced.motionScale < lowPower.motionScale)
    }

    @Test func packsAllEightBandsInFrequencyOrder() {
        let start = clock.now
        let bands = SIMD8<Float>(0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8)
        var state = RippleAnimationState(at: start)
        state.retarget(
            to: input(
                snapshot: SpectrumSnapshot(bands: bands, rms: 0.5, peak: 0.5),
                receivedAt: start
            ),
            at: start
        )
        let uniforms = state.uniforms(
            at: start.advanced(by: .milliseconds(120))
        )
        let factor: Float = 0.63212055
        #expect(abs(uniforms.bandsLow.x - 0.1 * factor) < 0.0001)
        #expect(abs(uniforms.bandsLow.y - 0.2 * factor) < 0.0001)
        #expect(abs(uniforms.bandsLow.z - 0.3 * factor) < 0.0001)
        #expect(abs(uniforms.bandsLow.w - 0.4 * factor) < 0.0001)
        #expect(abs(uniforms.bandsHigh.x - 0.5 * factor) < 0.0001)
        #expect(abs(uniforms.bandsHigh.y - 0.6 * factor) < 0.0001)
        #expect(abs(uniforms.bandsHigh.z - 0.7 * factor) < 0.0001)
        #expect(abs(uniforms.bandsHigh.w - 0.8 * factor) < 0.0001)
    }
}
```

- [ ] **Step 2: Regenerate and run the animation suite to verify RED**

```bash
tuist generate --no-open
xcodebuild test \
  -workspace Sculptor.xcworkspace \
  -scheme Sculptor-Workspace \
  -destination "platform=iOS Simulator,name=${SIM:-iPhone 16}" \
  -only-testing:SculptorTests/RippleAnimationStateTests \
  > /tmp/ripple-state-red.log 2>&1
status=$?
tail -80 /tmp/ripple-state-red.log
exit $status
```

Expected: build failure because the ripple animation types are undefined.

- [ ] **Step 3: Implement the pure anchor-based animation state**

Create `Sculptor/Sources/RippleAnimationState.swift`:

```swift
import AudioEngine
import Darwin
import Foundation

struct RippleAnimationInput: Equatable, Sendable {
    let snapshot: SpectrumSnapshot
    let receivedAt: ContinuousClock.Instant?
    let isPlaying: Bool
    let masterVolume: Float
    let isActive: Bool
    let reduceMotion: Bool
    let lowPowerMode: Bool
}

struct RippleMotionProfile: Equatable, Sendable {
    let minimumInterval: Double
    let motionScale: Float
    let detailScale: Float
    let peakScale: Float

    static func resolve(
        reduceMotion: Bool,
        lowPowerMode: Bool
    ) -> RippleMotionProfile {
        if reduceMotion {
            return RippleMotionProfile(
                minimumInterval: 1.0 / 30.0,
                motionScale: 0.2,
                detailScale: 0,
                peakScale: 0
            )
        }
        if lowPowerMode {
            return RippleMotionProfile(
                minimumInterval: 1.0 / 30.0,
                motionScale: 0.65,
                detailScale: 0,
                peakScale: 0.6
            )
        }
        return RippleMotionProfile(
            minimumInterval: 1.0 / 60.0,
            motionScale: 1,
            detailScale: 1,
            peakScale: 1
        )
    }
}

struct RippleUniforms: Equatable, Sendable {
    let bandsLow: SIMD4<Float>
    let bandsHigh: SIMD4<Float>
    let rms: Float
    let peak: Float
    let audioResponseScale: Float
    let motionScale: Float
    let detailScale: Float
    let elapsedTime: Float
}

struct RippleAnimationState: Sendable {
    private static let attackSeconds: Float = 0.120
    private static let releaseSeconds: Float = 0.450
    private static let peakReleaseSeconds: Float = 0.250
    private static let staleAfter = Duration.milliseconds(350)

    private var anchorInstant: ContinuousClock.Instant
    private var anchorSpectrum = SpectrumSnapshot.zero
    private var elapsedAtAnchor: Float = 0
    private var input: RippleAnimationInput

    init(at instant: ContinuousClock.Instant) {
        anchorInstant = instant
        input = RippleAnimationInput(
            snapshot: .zero,
            receivedAt: nil,
            isPlaying: false,
            masterVolume: 1,
            isActive: false,
            reduceMotion: false,
            lowPowerMode: false
        )
    }

    mutating func retarget(
        to newInput: RippleAnimationInput,
        at instant: ContinuousClock.Instant
    ) {
        anchorSpectrum = displayedSpectrum(at: instant)
        elapsedAtAnchor = elapsedTime(at: instant)
        anchorInstant = instant
        input = newInput
    }

    func uniforms(
        at instant: ContinuousClock.Instant
    ) -> RippleUniforms {
        let displayed = displayedSpectrum(at: instant)
        let profile = RippleMotionProfile.resolve(
            reduceMotion: input.reduceMotion,
            lowPowerMode: input.lowPowerMode
        )
        let response = input.isActive
            ? Self.clamp(input.masterVolume)
            : 0

        return RippleUniforms(
            bandsLow: SIMD4<Float>(
                displayed.bands[0], displayed.bands[1],
                displayed.bands[2], displayed.bands[3]
            ),
            bandsHigh: SIMD4<Float>(
                displayed.bands[4], displayed.bands[5],
                displayed.bands[6], displayed.bands[7]
            ),
            rms: displayed.rms,
            peak: displayed.peak * profile.peakScale,
            audioResponseScale: response,
            motionScale: profile.motionScale,
            detailScale: profile.detailScale,
            elapsedTime: elapsedTime(at: instant)
        )
    }

    private func displayedSpectrum(
        at instant: ContinuousClock.Instant
    ) -> SpectrumSnapshot {
        guard input.isPlaying, input.isActive,
              let receivedAt = input.receivedAt else {
            return Self.interpolate(
                from: anchorSpectrum,
                to: .zero,
                elapsed: Self.seconds(anchorInstant.duration(to: instant))
            )
        }

        let staleInstant = receivedAt.advanced(by: Self.staleAfter)
        if anchorInstant >= staleInstant {
            return Self.interpolate(
                from: anchorSpectrum,
                to: .zero,
                elapsed: Self.seconds(anchorInstant.duration(to: instant))
            )
        }
        if instant <= staleInstant {
            return Self.interpolate(
                from: anchorSpectrum,
                to: input.snapshot,
                elapsed: Self.seconds(anchorInstant.duration(to: instant))
            )
        }

        let atStaleBoundary = Self.interpolate(
            from: anchorSpectrum,
            to: input.snapshot,
            elapsed: Self.seconds(anchorInstant.duration(to: staleInstant))
        )
        return Self.interpolate(
            from: atStaleBoundary,
            to: .zero,
            elapsed: Self.seconds(staleInstant.duration(to: instant))
        )
    }

    private func elapsedTime(
        at instant: ContinuousClock.Instant
    ) -> Float {
        guard input.isActive else { return elapsedAtAnchor }
        return elapsedAtAnchor
            + Self.seconds(anchorInstant.duration(to: instant))
    }

    private static func interpolate(
        from start: SpectrumSnapshot,
        to target: SpectrumSnapshot,
        elapsed: Float
    ) -> SpectrumSnapshot {
        var bands = SIMD8<Float>.zero
        for index in 0..<8 {
            bands[index] = envelope(
                from: start.bands[index],
                to: target.bands[index],
                elapsed: elapsed,
                release: releaseSeconds
            )
        }
        return SpectrumSnapshot(
            bands: bands,
            rms: envelope(
                from: start.rms,
                to: target.rms,
                elapsed: elapsed,
                release: releaseSeconds
            ),
            peak: envelope(
                from: start.peak,
                to: target.peak,
                elapsed: elapsed,
                release: peakReleaseSeconds
            )
        )
    }

    private static func envelope(
        from start: Float,
        to target: Float,
        elapsed: Float,
        release: Float
    ) -> Float {
        let timeConstant = target >= start ? attackSeconds : release
        let factor = Float(Darwin.exp(-Double(max(0, elapsed) / timeConstant)))
        return clamp(target + (start - target) * factor)
    }

    private static func seconds(_ duration: Duration) -> Float {
        let components = duration.components
        let whole = Float(components.seconds)
        let fractional = Float(components.attoseconds)
            / 1_000_000_000_000_000_000
        return max(0, whole + fractional)
    }

    private static func clamp(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }
}
```

- [ ] **Step 4: Run the animation suite to verify GREEN**

```bash
tuist generate --no-open
xcodebuild test \
  -workspace Sculptor.xcworkspace \
  -scheme Sculptor-Workspace \
  -destination "platform=iOS Simulator,name=${SIM:-iPhone 16}" \
  -only-testing:SculptorTests/RippleAnimationStateTests \
  > /tmp/ripple-state-green.log 2>&1
```

Expected: all attack, release, stale timeout, paused drift, inactive freeze, motion-profile, and packing tests pass without waiting on real time.

- [ ] **Step 5: Commit the animation model**

```bash
git add \
  Sculptor/Sources/RippleAnimationState.swift \
  Sculptor/Tests/RippleAnimationStateTests.swift
git commit -m "feat(ui): add ripple animation model"
```

---

### Task 8: Procedural Metal Living Contours Renderer

**Files:**

- Create: `Sculptor/Sources/Shaders/LivingContours.metal`
- Create: `Sculptor/Sources/RippleBackground.swift`
- Create: `Sculptor/Tests/RippleBackgroundTests.swift`

**Interfaces:**

- Consumes: `RippleAnimationInput`, `RippleMotionProfile`, `RippleAnimationState`, and `RippleUniforms` from Task 7; `DockColor.accent` from DesignSystem.
- Produces: `RippleBackground.init(snapshot:spectrumReceivedAt:isPlaying:masterVolume:isActive:)` and default-library stitchable function `livingContours`.
- Swift argument order after the injected `position` must exactly match the MSL signature.

- [ ] **Step 1: Write the renderer input-contract test**

Create `Sculptor/Tests/RippleBackgroundTests.swift`:

```swift
import AudioEngine
import Testing
@testable import Sculptor

@MainActor
@Suite("Ripple background")
struct RippleBackgroundTests {
    @Test func requiredInputsAreRetained() {
        let now = ContinuousClock().now
        let view = RippleBackground(
            snapshot: .zero,
            spectrumReceivedAt: now,
            isPlaying: true,
            masterVolume: 0.4,
            isActive: true
        )

        #expect(view.snapshot == .zero)
        #expect(view.spectrumReceivedAt == now)
        #expect(view.isPlaying)
        #expect(abs(view.masterVolume - 0.4) < 0.0001)
        #expect(view.isActive)
    }
}
```

- [ ] **Step 2: Regenerate and run the focused test to verify RED**

```bash
tuist generate --no-open
xcodebuild test \
  -workspace Sculptor.xcworkspace \
  -scheme Sculptor-Workspace \
  -destination "platform=iOS Simulator,name=${SIM:-iPhone 16}" \
  -only-testing:SculptorTests/RippleBackgroundTests \
  > /tmp/ripple-background-red.log 2>&1
status=$?
tail -80 /tmp/ripple-background-red.log
exit $status
```

Expected: build failure because `RippleBackground` does not exist.

- [ ] **Step 3: Add the one-pass stitchable Metal shader**

Create `Sculptor/Sources/Shaders/LivingContours.metal`:

```metal
#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

static float contourHash(float2 point) {
    point = fract(point * float2(123.34, 456.21));
    point += dot(point, point + 45.32);
    return fract(point.x * point.y);
}

static float contourNoise(float2 point) {
    float2 cell = floor(point);
    float2 local = fract(point);
    float2 blend = local * local * (3.0 - 2.0 * local);
    float lowerLeft = contourHash(cell);
    float lowerRight = contourHash(cell + float2(1.0, 0.0));
    float upperLeft = contourHash(cell + float2(0.0, 1.0));
    float upperRight = contourHash(cell + float2(1.0, 1.0));
    return mix(
        mix(lowerLeft, lowerRight, blend.x),
        mix(upperLeft, upperRight, blend.x),
        blend.y
    );
}

static float contourFBM(float2 point, float detailScale) {
    float value = contourNoise(point) * 0.67;
    if (detailScale > 0.5) {
        value += contourNoise(point * 2.03 + 7.17) * 0.33;
    }
    return value * 2.0 - 1.0;
}

static float2 contourRotate(float2 point, float angle) {
    float sine = sin(angle);
    float cosine = cos(angle);
    return float2(
        cosine * point.x - sine * point.y,
        sine * point.x + cosine * point.y
    );
}

[[ stitchable ]]
half4 livingContours(
    float2 position,
    float2 canvasSize,
    float elapsedTime,
    float4 bandsLow,
    float4 bandsHigh,
    float rms,
    float peak,
    float audioResponseScale,
    float motionScale,
    float detailScale,
    half4 accent
) {
    if (canvasSize.x <= 0.0 || canvasSize.y <= 0.0) {
        return half4(0.0h);
    }
    float shortestSide = max(min(canvasSize.x, canvasSize.y), 1.0);
    float2 point = (position - canvasSize * 0.5) / shortestSide;
    float time = fmod(max(elapsedTime, 0.0), 168.0);
    float response = clamp(audioResponseScale, 0.0, 1.0);

    float bass60 = bandsLow.x;
    float bass125 = bandsLow.y;
    float bass250 = bandsLow.z;
    float mid500 = bandsLow.w;
    float mid1k = bandsHigh.x;
    float mid2k = bandsHigh.y;
    float high4k = bandsHigh.z;
    float high8k = bandsHigh.w;
    float totalEnergy = clamp(rms * response, 0.0, 1.0);
    float peakEnergy = clamp(peak * response, 0.0, 1.0);
    float audioMotion = totalEnergy * clamp(motionScale, 0.0, 1.0);

    float preservedDrift = mix(
        0.35,
        1.0,
        clamp(motionScale, 0.0, 1.0)
    );
    float2 drift = float2(
        sin(time * (2.0 * M_PI_F / 11.0) + mid2k * audioMotion * 0.7),
        cos(time * (2.0 * M_PI_F / 13.0) - mid2k * audioMotion * 0.5)
    ) * (0.035 + mid2k * audioMotion * 0.020) * preservedDrift;
    point -= drift;

    float rotation = (
        sin(time * (2.0 * M_PI_F / 14.0)) * 0.22 * motionScale
        + mid1k * audioMotion * 0.14
        - mid2k * audioMotion * 0.08
    );
    point = contourRotate(point, rotation);

    float lineMask = 0.0;
    float glowMask = 0.0;
    for (int index = 0; index < 4; ++index) {
        float contourIndex = float(index);
        float radius = 0.26
            + contourIndex * (0.16 + bass125 * audioMotion * 0.012);
        radius += bass60 * audioMotion
            * (0.022 + contourIndex * 0.005);

        float angle = atan2(point.y, point.x);
        float lobe = sin(
            angle * (2.0 + contourIndex)
            + time * (0.18 + contourIndex * 0.025)
            + mid500 * audioMotion * 1.2
            + mid1k * audioMotion * 0.8
        );
        float breathing = sin(
            time * (2.0 * M_PI_F / (8.0 + contourIndex * 1.7))
            + contourIndex * 1.4
        );
        float2 noisePoint = point * (3.1 + contourIndex * 0.55);
        noisePoint += float2(time * 0.018, -time * 0.014);
        float noise = contourFBM(noisePoint, detailScale);

        float baselineDeformation = (
            lobe * 0.018 + breathing * 0.014 + noise * 0.022
        ) * motionScale;
        float audioDeformation = audioMotion * (
            bass250 * breathing * 0.032
            + mid500 * lobe * 0.018
            + mid1k * sin(angle * 3.0 - time * 0.13) * 0.018
            + mid2k * cos(angle * 5.0 + time * 0.17) * 0.014
            + high4k * noise * 0.016
        );

        float signedDistance = abs(
            length(point) - radius
            - baselineDeformation
            - audioDeformation
        );
        float antialias = max(fwidth(signedDistance), 0.001);
        float lineWidth = 0.0055 + high4k * totalEnergy * 0.0025;
        float glowWidth = lineWidth + 0.020
            + high8k * totalEnergy * 0.012;
        float contourLine = 1.0 - smoothstep(
            lineWidth,
            lineWidth + antialias,
            signedDistance
        );
        float contourGlow = 1.0 - smoothstep(
            lineWidth,
            glowWidth + antialias,
            signedDistance
        );
        lineMask = max(lineMask, contourLine);
        glowMask = max(glowMask, contourGlow);
    }

    float lineAlpha = clamp(
        0.10 + totalEnergy * 0.16 + peakEnergy * 0.04,
        0.10,
        0.30
    );
    float glowAlpha = clamp(
        totalEnergy * (0.10 + high4k * 0.03 + high8k * 0.05),
        0.0,
        0.18
    );
    float alpha = max(lineMask * lineAlpha, glowMask * glowAlpha);
    half outputAlpha = half(clamp(alpha, 0.0, 0.30));
    return half4(accent.rgb * outputAlpha, outputAlpha);
}
```

This mapping is fixed: 60/125/250 Hz control radius/spacing/breathing; 500/1k/2k control lobes/rotation/drift; 4k/8k control edge noise/glow; RMS controls total response; peak adds at most `0.04` line alpha.

- [ ] **Step 4: Bind monotonic animation state to the shader**

Create `Sculptor/Sources/RippleBackground.swift`:

```swift
import AudioEngine
import Combine
import DesignSystem
import Foundation
import SwiftUI

struct RippleBackground: View {
    let snapshot: SpectrumSnapshot
    let spectrumReceivedAt: ContinuousClock.Instant?
    let isPlaying: Bool
    let masterVolume: Float
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lowPowerMode: Bool
    @State private var animationState: RippleAnimationState
    private let clock: ContinuousClock

    init(
        snapshot: SpectrumSnapshot,
        spectrumReceivedAt: ContinuousClock.Instant?,
        isPlaying: Bool,
        masterVolume: Float,
        isActive: Bool
    ) {
        let clock = ContinuousClock()
        self.snapshot = snapshot
        self.spectrumReceivedAt = spectrumReceivedAt
        self.isPlaying = isPlaying
        self.masterVolume = masterVolume
        self.isActive = isActive
        self.clock = clock
        _lowPowerMode = State(
            initialValue: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
        _animationState = State(
            initialValue: RippleAnimationState(at: clock.now)
        )
    }

    private var input: RippleAnimationInput {
        RippleAnimationInput(
            snapshot: snapshot,
            receivedAt: spectrumReceivedAt,
            isPlaying: isPlaying,
            masterVolume: masterVolume,
            isActive: isActive,
            reduceMotion: reduceMotion,
            lowPowerMode: lowPowerMode
        )
    }

    private var profile: RippleMotionProfile {
        RippleMotionProfile.resolve(
            reduceMotion: reduceMotion,
            lowPowerMode: lowPowerMode
        )
    }

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: profile.minimumInterval,
                paused: !isActive
            )
        ) { _ in
            GeometryReader { proxy in
                // TimelineView supplies the tick; sample its monotonic instant
                // once and pass that explicit value into the pure state.
                let tickInstant = clock.now
                let uniforms = animationState.uniforms(at: tickInstant)
                Rectangle()
                    .fill(shader(size: proxy.size, uniforms: uniforms))
            }
        }
        .onChange(of: input, initial: true) { _, newInput in
            animationState.retarget(to: newInput, at: clock.now)
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .NSProcessInfoPowerStateDidChange
            )
        ) { _ in
            lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func shader(
        size: CGSize,
        uniforms: RippleUniforms
    ) -> Shader {
        ShaderLibrary.livingContours(
            .float2(size),
            .float(uniforms.elapsedTime),
            .float4(
                uniforms.bandsLow.x,
                uniforms.bandsLow.y,
                uniforms.bandsLow.z,
                uniforms.bandsLow.w
            ),
            .float4(
                uniforms.bandsHigh.x,
                uniforms.bandsHigh.y,
                uniforms.bandsHigh.z,
                uniforms.bandsHigh.w
            ),
            .float(uniforms.rms),
            .float(uniforms.peak),
            .float(uniforms.audioResponseScale),
            .float(uniforms.motionScale),
            .float(uniforms.detailScale),
            .color(DockColor.accent)
        )
    }
}
```

`TimelineView` exposes a wall-clock `Date`, not a `ContinuousClock.Instant`. Sampling the stored monotonic clock exactly once inside each timeline invocation produces the explicit per-tick instant passed to `uniforms(at:)`; the pure animation state never reads a clock internally.

- [ ] **Step 5: Regenerate and verify test GREEN plus MSL compilation**

```bash
tuist generate --no-open

xcodebuild test \
  -workspace Sculptor.xcworkspace \
  -scheme Sculptor-Workspace \
  -destination "platform=iOS Simulator,name=${SIM:-iPhone 16}" \
  -only-testing:SculptorTests/RippleBackgroundTests \
  > /tmp/ripple-background-green.log 2>&1

xcodebuild build \
  -workspace Sculptor.xcworkspace \
  -scheme Sculptor-Workspace \
  -destination "generic/platform=iOS Simulator" \
  > /tmp/ripple-metal-build.log 2>&1
```

Expected: the test passes and `LivingContours.metal` compiles into the app target's default Metal library. This does not yet prove dynamic shader lookup; Task 10 performs the required runtime smoke.

- [ ] **Step 6: Commit the renderer**

```bash
git add \
  Sculptor/Sources/RippleBackground.swift \
  Sculptor/Sources/Shaders/LivingContours.metal \
  Sculptor/Tests/RippleBackgroundTests.swift
git commit -m "feat(ui): render Metal living contours"
```

---

### Task 9: Home Integration, Legacy Removal, and Durable Documentation

**Files:**

- Modify: `Sculptor/Sources/HomeView.swift:14-25`
- Delete: `Packages/DesignSystem/Sources/DesignSystem/Components/ScopeVisualizer.swift`
- Delete: `Packages/DesignSystem/Tests/DesignSystemTests/ScopeVisualizerTests.swift`
- Delete: `Packages/AudioEngine/Sources/AudioEngine/Downsample.swift`
- Delete: `Packages/AudioEngine/Tests/AudioEngineTests/DownsampleTests.swift`
- Modify: `docs/sculptor_design/Sculptor.dc.html:15-24,33,43-82,403,421-422`
- Modify: `README.md:12,35-39`
- Modify: `CLAUDE.md:14-28,44-55`
- Modify: `Scripts/test-all.sh:2-4`

**Interfaces:**

- Consumes: Home spectrum/lifecycle properties from Task 6 and `RippleBackground` from Task 8.
- Produces: final Home-only Z-stack ordering and zero production references to scope/downsample APIs.
- Preserves: opaque Sculpt sheet, full-screen Presets presentation, all controls, and PHONE volume behavior.

- [ ] **Step 1: Prove legacy implementation remains before removal**

```bash
rg -n \
  'ScopeVisualizer|ScopeGeometry|onScopeSamples|scopeSamples|scopeEnabled|isScopeTapInstalled|_installScopeTap|_removeScopeTap|Downsample' \
  Sculptor Packages \
  --glob '*.swift' \
  > /tmp/ripple-legacy-before.log
test -s /tmp/ripple-legacy-before.log
```

Expected: matches are confined to the two obsolete DesignSystem files and two Downsample files. Any caller means Task 5 or Task 6 is not green; return to that task before continuing.

- [ ] **Step 2: Insert RippleBackground between Home's base color and foreground**

Replace `HomeView.body` with:

```swift
var body: some View {
    ZStack {
        DockColor.background.ignoresSafeArea()

        RippleBackground(
            snapshot: vm.spectrumSnapshot,
            spectrumReceivedAt: vm.spectrumReceivedAt,
            isPlaying: vm.isPlaying,
            masterVolume: vm.masterVolume,
            isActive: vm.visualizationActive
        )
        .ignoresSafeArea()

        VStack(spacing: 0) {
            topBar
            Spacer()
            heroCenter
            Spacer()
            bottomRail
        }
    }
    .onChange(of: presetName, initial: true) { _, name in
        vm.nowPlayingTitle = name
    }
}
```

`RippleBackground` already disables hit testing and accessibility. Do not add it to `RootView`, `SculptSheet`, or `PresetsView`.

- [ ] **Step 3: Delete obsolete scope and downsample files**

Delete these four complete files:

```text
Packages/DesignSystem/Sources/DesignSystem/Components/ScopeVisualizer.swift
Packages/DesignSystem/Tests/DesignSystemTests/ScopeVisualizerTests.swift
Packages/AudioEngine/Sources/AudioEngine/Downsample.swift
Packages/AudioEngine/Tests/AudioEngineTests/DownsampleTests.swift
```

- [ ] **Step 4: Update the design source of truth to living contours**

In `docs/sculptor_design/Sculptor.dc.html`, remove the `scPulse` and `scEq` keyframes and add:

```css
  @keyframes scContourDrift {
    0%,100% { transform:translate(-5px,3px) rotate(-2deg) scale(0.98); }
    50% { transform:translate(7px,-5px) rotate(3deg) scale(1.025); }
  }
  .sc-contour-field {
    transform-box:fill-box;
    transform-origin:center;
    animation:scContourDrift 11s ease-in-out infinite;
  }
```

Replace the descriptive header paragraph with:

```html
    <div style="font-size:13px; color:#6c737f; margin-top:3px; max-width:820px;">No tab bar. Now Playing is home with a constant, gently drifting <b>living-contour background</b> that responds to the real post-EQ spectrum while playing. <b>Presets</b> is a button top-right; <b>Sculpt</b> opens as an opaque bottom sheet and leaves contours visible only around the uncovered Home area. Presets covers and pauses the Home effect.</div>
```

Immediately inside Frame 1's device container, before the padded foreground, add this always-animating four-contour field:

```html
          <svg viewBox="0 0 402 874" aria-hidden="true" style="position:absolute; inset:0; width:100%; height:100%; pointer-events:none; overflow:visible;">
            <g class="sc-contour-field" fill="none" stroke="#2ED3B7" stroke-linecap="round">
              <path d="M45 455 C34 323 105 176 213 185 C321 194 380 325 353 452 C327 579 271 697 163 681 C55 665 55 570 45 455 Z" stroke-width="1.2" opacity="0.10"></path>
              <path d="M76 458 C65 347 121 226 210 230 C299 234 348 341 329 451 C310 561 264 642 176 629 C88 616 86 569 76 458 Z" stroke-width="1.3" opacity="0.13"></path>
              <path d="M109 458 C102 372 142 278 211 281 C280 284 316 365 301 450 C286 535 254 588 187 579 C120 570 116 544 109 458 Z" stroke-width="1.4" opacity="0.16"></path>
              <path d="M143 457 C137 398 164 329 213 332 C262 335 285 391 275 451 C265 511 244 539 199 531 C154 523 149 516 143 457 Z" stroke-width="1.5" opacity="0.19"></path>
            </g>
          </svg>
```

Add `position:relative; z-index:1;` to Frame 1's padded foreground style. Delete the three `scPulse` circle divs around the play control. Delete the complete `eqBars` `<sc-for>` block and change the play-hint top margin to `26px`:

```html
              <div style="font-size:12px; color:#62626A; margin-top:26px;">{{ playHint }}</div>
```

Delete this JavaScript declaration:

```javascript
    const eqBars = Array.from({ length: 22 }, (_, i) => ({ h: (24 + Math.abs(Math.sin(i * 1.3)) * 66 + (i % 3) * 4).toFixed(0) + '%', delay: ((i % 7) * 0.1).toFixed(2) + 's' }));
```

Replace the complete returned object with:

```javascript
    return {
      playState, presetName, edited: st.edited, sliders, presetChips, dials,
      playIcon: st.playing ? '--dock-icon-pause' : '--dock-icon-play-arrow',
      playIconShift: st.playing ? '0' : '6px',
      playHint: st.playing ? 'Playing · tap to pause' : 'Paused · tap to play',
      togglePlay: () => this.togglePlay(),
      resetBands: () => this.resetBands(),
      saveBg: st.edited ? '#0f2622' : 'transparent',
      saveColor: st.edited ? '#2ED3B7' : '#95959D',
      saveLabel: st.edited ? 'Save as preset' : 'Saved',
      savePreset: () => this.savePreset(),
      builtinList, userList,
      renameValue: st.renameValue,
      onRenameChange: (e) => this.setState({ renameValue: e.target.value }),
      onRenameKey: (e) => { if (e.key === 'Enter') this.commitRename(); },
    };
```

This removes only `eqBars` and `barOpacity` from the render data.

Immediately inside Frame 2's device container, before the dimmed Now Playing layer, add the contour field explicitly so the uncovered area above the opaque Sculpt sheet reflects the approved compositing behavior:

```html
          <svg viewBox="0 0 402 874" aria-hidden="true" style="position:absolute; inset:0; width:100%; height:100%; pointer-events:none; overflow:visible;">
            <g class="sc-contour-field" fill="none" stroke="#2ED3B7" stroke-linecap="round">
              <path d="M45 455 C34 323 105 176 213 185 C321 194 380 325 353 452 C327 579 271 697 163 681 C55 665 55 570 45 455 Z" stroke-width="1.2" opacity="0.10"></path>
              <path d="M76 458 C65 347 121 226 210 230 C299 234 348 341 329 451 C310 561 264 642 176 629 C88 616 86 569 76 458 Z" stroke-width="1.3" opacity="0.13"></path>
              <path d="M109 458 C102 372 142 278 211 281 C280 284 316 365 301 450 C286 535 254 588 187 579 C120 570 116 544 109 458 Z" stroke-width="1.4" opacity="0.16"></path>
              <path d="M143 457 C137 398 164 329 213 332 C262 335 285 391 275 451 C265 511 244 539 199 531 C154 523 149 516 143 457 Z" stroke-width="1.5" opacity="0.19"></path>
            </g>
          </svg>
```

- [ ] **Step 5: Update README, repository guidance, and test runner comments**

In `README.md`, replace the oscilloscope feature bullet with:

```markdown
- **Audio-reactive living contours** — a full-screen procedural Metal background driven by the real post-EQ eight-band spectrum, with calm paused drift and reduced Low Power/Reduce Motion profiles.
```

Replace the Testing command with this fenced command:

```text
Scripts/test-all.sh   # full suite across AudioEngine, DesignSystem, and Sculptor
```

In `CLAUDE.md`, use these count-free command descriptions:

```markdown
Scripts/test-all.sh           # FULL test suite across all three schemes

# app tests — from repo root
xcodebuild test -workspace Sculptor.xcworkspace -scheme Sculptor-Workspace -destination "platform=iOS Simulator,name=iPhone 16"

# package tests — from inside each package directory
cd Packages/AudioEngine  && xcodebuild test -scheme AudioEngine  -destination "platform=iOS Simulator,name=iPhone 16"
cd Packages/DesignSystem && xcodebuild test -scheme DesignSystem -destination "platform=iOS Simulator,name=iPhone 16"
```

Replace the count-bearing warning below that block with:

```markdown
A green `Sculptor-Workspace` run alone is NOT "tests pass" — it silently skips both package suites.
```

Replace the complete `## Architecture` section in `CLAUDE.md` with:

```markdown
## Architecture

Three modules, strict dependency direction: `Sculptor (app) → Packages/AudioEngine + Packages/DesignSystem` (packages don't know each other or the app).

**Packages/AudioEngine** — the defensible UI-free core.
- `NoiseEngine` owns `AVAudioSourceNode (synth noise) → 8-band AVAudioUnitEQ → mainMixer`, post-EQ spectrum capture/analysis, fade-out, interruption/route/media-reset recovery, and the background-audio session. Control state is `@MainActor`; the render callback uses only preallocated source state and a raw spectrum submission handle.
- `SpectrumMailbox` uses the local `RealtimeAtomics` C11 target for iOS 17-compatible lock-free slot transitions. `SpectrumAnalyzer` polls the newest complete frame and reuses `SpectrumFFT`/Accelerate storage.
- Pure decision logic remains in caseless enums: `AudioSessionPolicy`, `Fade`, and `NoisePreset`.

**Packages/DesignSystem** — Dock/Blinkit visual layer, app-agnostic components.
- `Tokens/` provides `DockColor`, `DockType`, and `DockMetrics`; `Components/` provides `PlayHeroButton`, `VolumeKnob`/`KnobGeometry`, `BandSlider`, `MiniEQIcon`, `PresetRow`, `PresetChip`, and `DockCard`.
- Lexend fonts are SPM resources. Their filenames are `Lexend-*`, but internal PostScript names are `Dock-Lexend-*`; `Font.custom`/`UIFont(name:)` must use the internal names and `FontRegistrar.registerFonts()` must run at app start.
- View geometry remains in caseless enums such as `SliderGeometry` and `MiniEQGeometry`.

**Sculptor (app)** — SwiftUI shell, no tab bar.
- `RootView` owns one `PlaybackViewModel` and navigation state. Home renders `RippleBackground` behind its controls; Sculpt is an opaque sheet that leaves the uncovered Home effect active; Presets is a full-screen cover that disables analysis/rendering.
- `PlaybackViewModel` coordinates gains, `PresetSelection`, edits, sleep timer, master volume, finite spectrum targets/timestamps, Home visibility, Now Playing, and Save→rename handoff.
- `RippleAnimationState` provides deterministic attack/release/stale decay. `RippleBackground` binds its uniforms to app-target `LivingContours.metal`.
- SwiftData persists `CustomPreset`; `SelectionPersistence` stores the active selection. `SystemVolume` bridges `AVAudioSession.outputVolume` and a hidden `MPVolumeView` for the PHONE knob.
```

In the Commands section, replace the single-test example with:

```bash
xcodebuild test ... -only-testing:AudioEngineTests/SpectrumFFTTests
```

Replace the first Conventions bullet with:

```markdown
- **No top-level Swift free functions.** Standalone Swift logic uses static methods on caseless enums. The prefixed `rt_atomic_u8_*` functions in the private C11 shim are the sole C ABI exception.
```

Replace `Scripts/test-all.sh:2-4` with:

```bash
# Full Sculptor test suite = 3 invocations because local-package schemes are
# invisible to -workspace. Counts are intentionally not hard-coded.
```

- [ ] **Step 6: Regenerate and prove all legacy Swift symbols are gone**

```bash
tuist generate --no-open

! rg -n \
  'ScopeVisualizer|ScopeGeometry|onScopeSamples|scopeSamples|scopeEnabled|isScopeTapInstalled|_installScopeTap|_removeScopeTap|Downsample' \
  Sculptor Packages \
  --glob '*.swift' \
  > /tmp/ripple-legacy-after.log
```

Expected: no matches and exit status 0. Scope terminology may remain only in superseded dated specs/plans, not maintained Swift code or current README/guidance.

- [ ] **Step 7: Run all three affected suites**

```bash
cd Packages/AudioEngine
xcodebuild test \
  -scheme AudioEngine \
  -destination "platform=iOS Simulator,name=${SIM:-iPhone 16}" \
  > /tmp/ripple-audioengine-integration.log 2>&1

cd ../DesignSystem
xcodebuild test \
  -scheme DesignSystem \
  -destination "platform=iOS Simulator,name=${SIM:-iPhone 16}" \
  > /tmp/ripple-designsystem-integration.log 2>&1

cd ../..
xcodebuild test \
  -workspace Sculptor.xcworkspace \
  -scheme Sculptor-Workspace \
  -destination "platform=iOS Simulator,name=${SIM:-iPhone 16}" \
  > /tmp/ripple-app-integration.log 2>&1
```

Expected: all three invocations report `TEST SUCCEEDED` after obsolete tests are removed and replacement tests are discovered.

- [ ] **Step 8: Commit Home integration and cleanup**

```bash
git add \
  Sculptor/Sources/HomeView.swift \
  docs/sculptor_design/Sculptor.dc.html \
  README.md \
  CLAUDE.md \
  Scripts/test-all.sh
git add -u \
  Packages/DesignSystem/Sources/DesignSystem/Components/ScopeVisualizer.swift \
  Packages/DesignSystem/Tests/DesignSystemTests/ScopeVisualizerTests.swift \
  Packages/AudioEngine/Sources/AudioEngine/Downsample.swift \
  Packages/AudioEngine/Tests/AudioEngineTests/DownsampleTests.swift
git commit -m "feat(app): replace scope with living contours"
```

---

### Task 10: End-to-End Verification and Runtime Shader Smoke

**Files:**

- Verify: all files changed in Tasks 1–9
- Verify: `docs/superpowers/specs/2026-07-12-audio-reactive-metal-ripple-design.md`
- No source file changes are expected in this task; fix any discovered defect in its owning task's file and rerun the affected gate before continuing.

**Interfaces:**

- Consumes: completed AudioEngine, Sculptor, DesignSystem, Metal, lifecycle, and documentation changes.
- Produces: evidence that tests pass, the lock-free handoff is race-free under TSan, dynamic shader lookup renders nonempty output, and remaining physical-device-only checks are either passed or explicitly reported.

- [ ] **Step 1: Use the Apple build workflow and run the canonical suite**

Before invoking Xcode developer tools, read and follow `apple-platform-build-tools:building-apple-platform-products`. Then run from the repository root:

```bash
SIM="${SIM:-iPhone 16}" Scripts/test-all.sh \
  > /tmp/sculptor-ripple-full-suite.log 2>&1
status=$?
tail -80 /tmp/sculptor-ripple-full-suite.log
exit $status
```

Expected: AudioEngine, DesignSystem, and Sculptor each report `TEST SUCCEEDED`. A green app scheme alone is not sufficient.

- [ ] **Step 2: Re-run the producer/consumer stress suite under TSan**

```bash
cd Packages/AudioEngine
xcodebuild test \
  -scheme AudioEngine \
  -destination "platform=iOS Simulator,name=${SIM:-iPhone 16}" \
  -enableThreadSanitizer YES \
  -only-testing:AudioEngineTests/SpectrumMailboxTests \
  -only-testing:AudioEngineTests/SpectrumAnalyzerTests \
  > /tmp/sculptor-ripple-mailbox-tsan.log 2>&1
```

Expected: `TEST SUCCEEDED` and no `ThreadSanitizer` warning, torn frame, non-monotonic sequence, worker-join failure, or teardown race.

- [ ] **Step 3: Build a known-path simulator app**

```bash
tuist generate --no-open
xcodebuild build \
  -workspace Sculptor.xcworkspace \
  -scheme Sculptor-Workspace \
  -destination "platform=iOS Simulator,name=${SIM:-iPhone 16}" \
  -derivedDataPath /tmp/SculptorRippleDerived \
  > /tmp/sculptor-ripple-smoke-build.log 2>&1
```

Expected: build succeeds, including `LivingContours.metal` compilation. Confirm the app exists:

```bash
test -d \
  /tmp/SculptorRippleDerived/Build/Products/Debug-iphonesimulator/Sculptor.app
```

- [ ] **Step 4: Boot, install, launch, and capture Home**

```bash
SIM="${SIM:-iPhone 16}"
if ! xcrun simctl list devices available | rg -q "$SIM.*Booted"; then
  xcrun simctl boot "$SIM"
fi
xcrun simctl bootstatus "$SIM" -b
xcrun simctl install booted \
  /tmp/SculptorRippleDerived/Build/Products/Debug-iphonesimulator/Sculptor.app
xcrun simctl launch --terminate-running-process \
  booted com.mishandled.sculptor
sleep 2
xcrun simctl io booted screenshot /tmp/sculptor-ripple-home.png
```

Inspect `/tmp/sculptor-ripple-home.png` with the image viewer. Expected: four nonempty translucent teal contours are visible behind the Home controls while paused, the former 80-point scope region is absent, knob spacing is exactly the enclosing `DockSpacing.lg`, and text/controls remain dominant.

- [ ] **Step 5: Check runtime shader diagnostics**

```bash
xcrun simctl spawn booted log show \
  --last 3m \
  --style compact \
  --predicate 'process == "Sculptor"' \
  > /tmp/sculptor-ripple-runtime.log

! rg -i \
  'failed to find.*livingContours|shader.*argument|metallib.*error|fatal error|crash' \
  /tmp/sculptor-ripple-runtime.log
```

Expected: no dynamic-member lookup, shader argument, Metal library, fatal, or crash error. This runtime check plus the nonempty screenshot—not MSL compilation alone—validates the Swift/MSL name and argument contract.

- [ ] **Step 6: Perform simulator interaction acceptance**

Interact with the launched app and verify each exact state:

- Paused Home: contours continue a gentle low-intensity drift with no flashing.
- Playing Home: contour response rises smoothly; stopping releases instead of freezing.
- Each of the eight Sculpt EQ bands: the next accepted frame produces a visible but balanced change matching its low/mid/high mapping.
- Sculpt sheet: contours remain visible only in Home's uncovered area; the sheet stays opaque.
- Presets: the full-screen page contains no ripple and analysis/rendering stop while it covers Home.
- NOISE at zero: audio-driven deformation disappears but baseline drift remains.
- PHONE volume changes: contour shape and band balance do not change.
- Background/foreground: leaving active scene stops analysis/timeline; returning restores it if audio is playing.
- Low Power Mode: cadence is 30 fps with one detail octave and reduced peak response.
- Reduce Motion: cadence is 30 fps, peak accent is absent, deformation is strongly reduced, and slow drift remains.

If any state fails, capture a screenshot/log, fix the owning component, then rerun the canonical suite, TSan gate, simulator build, runtime log check, and complete interaction checklist.

- [ ] **Step 7: Run physical-device performance acceptance when a device is attached**

```bash
xcrun devicectl list devices \
  > /tmp/sculptor-ripple-devices.txt 2>&1
```

If an available iOS device is listed, build/install the app with the repository's normal signing identity and profile a 60-second playing session in Instruments using Metal System Trace plus Time Profiler. Acceptance is:

Copy its identifier into `DEVICE_ID`, then run:

```bash
: "${DEVICE_ID:?Set DEVICE_ID to an available iOS device identifier}"

xcodebuild build \
  -workspace Sculptor.xcworkspace \
  -scheme Sculptor-Workspace \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath /tmp/SculptorRippleDevice \
  -allowProvisioningUpdates \
  > /tmp/sculptor-ripple-device-build.log 2>&1

xcrun devicectl device install app \
  --device "$DEVICE_ID" \
  /tmp/SculptorRippleDevice/Build/Products/Debug-iphoneos/Sculptor.app

xcrun devicectl device process launch \
  --device "$DEVICE_ID" \
  --terminate-existing \
  com.mishandled.sculptor

xcrun xctrace record \
  --template "Metal System Trace" \
  --device "$DEVICE_ID" \
  --time-limit 60s \
  --output /tmp/SculptorRippleMetal.trace \
  --attach Sculptor

xcrun xctrace record \
  --template "Time Profiler" \
  --device "$DEVICE_ID" \
  --time-limit 60s \
  --output /tmp/SculptorRippleTime.trace \
  --attach Sculptor
```

During both recordings, start playback and exercise several EQ bands. Inspect both traces against this acceptance list:

- no audio underrun or render-thread stall;
- analyzer queue never accumulates historical work (mailbox retains at most the newest pending window);
- normal Home rendering sustains display cadence;
- Low Power and Reduce Motion sustain their 30 fps target;
- no per-tap allocation, lock, semaphore, task, dispatch, or wake-up activity appears;
- one procedural full-screen Metal pass, with no texture/offscreen/blur pass introduced by this feature.

If no physical device is available, do not claim this item passed; report it as the sole outstanding device-only validation while still reporting simulator/test results precisely.

- [ ] **Step 8: Run the final repository audit**

```bash
git diff --check

! rg -n \
  'ScopeVisualizer|ScopeGeometry|onScopeSamples|scopeSamples|scopeEnabled|isScopeTapInstalled|_installScopeTap|_removeScopeTap|Downsample' \
  Sculptor Packages README.md CLAUDE.md Scripts \
  --glob '*.swift' \
  --glob '*.md' \
  --glob '*.sh'

rg -n \
  'livingContours|RippleBackground|SpectrumSnapshot|spectrumAnalysisEnabled' \
  Sculptor Packages README.md CLAUDE.md

git status --short --branch
```

Expected: no whitespace errors, no maintained legacy reference, all new pipeline/renderer symbols are present, and the worktree contains only the intended implementation-plan and feature changes. Review `git diff --stat` and `git diff` before reporting completion.

## Acceptance Traceability

- Home-only rendering and Sculpt/Presets behavior: Tasks 6, 9, and 10.
- Constant paused drift and balanced response: Tasks 7, 8, and 10.
- Eight post-EQ semantic bands, RMS, and peak: Tasks 1, 2, 5, and 8.
- Arbitrary tap chunks and bounded newest-frame backpressure: Tasks 3 and 4.
- Real-time safety, teardown, and late-completion rejection: Tasks 3–5 and 10.
- NOISE versus PHONE volume behavior: Tasks 7–10.
- Low Power and Reduce Motion profiles: Tasks 7, 8, and 10.
- Oscilloscope/downsample removal and layout recentering: Tasks 6 and 9.
- MSL compile plus dynamic runtime lookup: Tasks 8 and 10.
- Test, TSan, simulator, and device evidence: Task 10.
