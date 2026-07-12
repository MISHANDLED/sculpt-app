# Audio-Reactive Ripple Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the confirmed real-time ownership violation, bound spectrum delivery to the newest frame, eliminate main-thread audio-session negotiation, and leave media-reset recovery paused until explicit user action.

**Architecture:** AVAudioNode tap entry moves from Swift to a non-ARC Objective-C bridge that owns only the submission-storage owner for the complete lifetime of the installed block and calls one fixed raw C entry with a context pointer, sample pointer, and count. The analyzer remains independently owned so tap removal can be followed by immediate analyzer shutdown and deinitialization even when AVFAudio defers copied-block disposal. Analyzer results enter a lock-protected newest-only delivery gate that schedules at most one main-actor job and preserves the analysis timestamp. AVAudioSession configuration and activation run through one serialized background coordinator whose command generations prevent stale activate/deactivate operations from winning; NoiseEngine keeps graph mutation on MainActor and PlaybackViewModel owns the cancellable UI request.

**Tech Stack:** Swift 5 language mode, Swift 6 package manifest, Objective-C without ARC, C11 atomics, AVFAudio/AVFoundation, Dispatch, Swift Testing, Tuist, xcodebuild, arm64 object-code audits.

## Global Constraints

- Deployment floor remains iOS 17.0.
- Add no remote dependency.
- The AVAudio tap callback may perform bounded raw-memory reads/copies, scalar work, and lock-free atomics only. The required MRC bridge may invoke only the two non-owning `AVAudioPCMBuffer` getters specified below, then enter Swift solely through the raw C ABI `(void *, const float *, intptr_t)` submission function. No Swift bridge may accept Objective-C arguments, and no callback-chain symbol may perform ARC ownership changes, heap allocation, locking, semaphore operations, `Task`, dispatch/wakeup, or a blocking wait.
- Post-EQ capture remains on the EQ output and preserves exactly eight semantic bands plus RMS and peak.
- Backpressure is newest-only at both the audio-window mailbox and the main-actor delivery boundary; historical work must not accumulate.
- MainActor continues to own AVAudioEngine graph, playback, fade, analyzer, tap, and published UI mutation.
- Blocking AVAudioSession category/activation/deactivation work never executes on the main thread.
- Stop/play/interruption command ordering must be deterministic under rapid play-stop-play and cancellation.
- Media-services reset rebuilds the graph and restores EQ values but remains paused until explicit user action, matching Apple guidance.
- Home-only rendering, gentle paused drift, NOISE scaling, PHONE independence, Low Power, and Reduce Motion behavior remain unchanged.
- Before every xcodebuild/xcrun command, follow `apple-platform-build-tools:building-apple-platform-products`; redirect xcodebuild stdout/stderr to a log file and never pipe xcodebuild.

---

### Task 1: Install the Spectrum Tap Through a Non-ARC Objective-C Bridge

**Files:**

- Modify: `Packages/AudioEngine/Package.swift`
- Modify: `Packages/AudioEngine/Sources/RealtimeAtomics/include/RealtimeAtomics.h`
- Create: `Packages/AudioEngine/Sources/RealtimeAtomics/RealtimeTapBridge.m`
- Modify: `Packages/AudioEngine/Sources/AudioEngine/SpectrumAnalyzer.swift`
- Modify: `Packages/AudioEngine/Sources/AudioEngine/SpectrumMailbox.swift`
- Modify: `Packages/AudioEngine/Sources/AudioEngine/NoiseEngine.swift`
- Modify: `Packages/AudioEngine/Tests/AudioEngineTests/NoiseEngineSpectrumTapTests.swift`
- Modify: `Packages/AudioEngine/Tests/AudioEngineTests/SpectrumMailboxTests.swift`
- Create: `Scripts/audit-realtime-tap.sh`
- Create: `Scripts/test-audit-realtime-tap.sh`
- Create: `Scripts/Fixtures/RealtimeTapAudit/`

**Interfaces:**

- Consumes: `SpectrumSubmission.context`, whose storage conforms to the fixed mailbox producer ABI.
- Produces: `rt_spectrum_mailbox_submit(void *, const float *, intptr_t)` as the only audio-thread submit target.
- Produces: `rt_audio_node_install_spectrum_tap(...)` with raw node, submit context, and lifetime context.
- Produces: a tap block that retains the submission-storage owner only when the block is copied and releases it only when the block is disposed.
- Preserves: `NoiseEngine._removeSpectrumTap()` removes the tap before analyzer shutdown.

- [ ] **Step 1: Add the failing outer-boundary audit**

Create `Scripts/audit-realtime-tap.sh` so it accepts a DerivedData root, locates arm64 `NoiseEngine.o` and `RealtimeTapBridge.o`, and fails when either condition is false:

```bash
#!/bin/bash
set -euo pipefail

ROOT="${1:?usage: audit-realtime-tap.sh DERIVED_DATA_ROOT}"
NOISE_OBJECT="$(find "$ROOT" -path '*Objects-normal/arm64/NoiseEngine.o' -print -quit)"
BRIDGE_OBJECT="$(find "$ROOT" -path '*Objects-normal/arm64/RealtimeTapBridge.o' -print -quit)"

test -n "$NOISE_OBJECT"
test -n "$BRIDGE_OBJECT"

if nm -nm "$NOISE_OBJECT" | rg -q 'AVAudioPCMBuffer.*Ieggg_AbDIeyByy_TR'; then
  echo 'Swift AVAudioPCMBuffer tap thunk is still present' >&2
  exit 1
fi

CALLBACKS="$(nm -nm "$BRIDGE_OBJECT" | awk '/rt_spectrum_tap.*block_invoke|rt_spectrum_tap_forward/ {print $3}')"
test -n "$CALLBACKS"
for symbol in $CALLBACKS; do
  if xcrun llvm-objdump --disassemble-symbols="$symbol" --reloc "$BRIDGE_OBJECT" \
    | rg -q 'swift_(retain|release)|objc_(retain|release)|objc_retainBlock'; then
    echo "ownership traffic in $symbol" >&2
    exit 1
  fi
done
```

Make it executable. Build the current Release AudioEngine into `/tmp/SculptorRippleTapRed`, run the audit, and preserve `/tmp/sculptor-ripple-tap-audit-red.log`.

Expected: FAIL because `RealtimeTapBridge.o` does not exist and the optimized Swift tap thunk is present.

- [ ] **Step 2: Declare the raw bridge contract**

Append to `RealtimeAtomics.h`:

```c
#include <stddef.h>

bool rt_spectrum_mailbox_submit(
    void *context,
    const float *samples,
    intptr_t count
);
typedef void (*RTSpectrumReleaseFunction)(void *context);

void rt_audio_node_install_spectrum_tap(
    void *node,
    uint32_t bus,
    uint32_t buffer_size,
    void *submit_context,
    void *lifetime_context,
    RTSpectrumReleaseFunction release_lifetime
);
```

- [ ] **Step 3: Implement the MRC bridge and lifetime owner**

Create `RealtimeTapBridge.m` with ARC forbidden at compile time:

```objective-c
#import "RealtimeAtomics.h"
#import <AVFAudio/AVFAudio.h>

#if __has_feature(objc_arc)
#error RealtimeTapBridge.m must be compiled with -fno-objc-arc
#endif

@interface RTSpectrumTapContext : NSObject {
@public
    void *_submitContext;
    void *_lifetimeContext;
    RTSpectrumReleaseFunction _releaseLifetime;
}
- (instancetype)initWithSubmitContext:(void *)submitContext
                       lifetimeContext:(void *)lifetimeContext
                       releaseLifetime:(RTSpectrumReleaseFunction)releaseLifetime;
@end

@implementation RTSpectrumTapContext
- (instancetype)initWithSubmitContext:(void *)submitContext
                       lifetimeContext:(void *)lifetimeContext
                       releaseLifetime:(RTSpectrumReleaseFunction)releaseLifetime {
    self = [super init];
    if (self != nil) {
        _submitContext = submitContext;
        _lifetimeContext = lifetimeContext;
        _releaseLifetime = releaseLifetime;
    }
    return self;
}

- (void)dealloc {
    if (_releaseLifetime != NULL) {
        _releaseLifetime(_lifetimeContext);
    }
    [super dealloc];
}
@end

__attribute__((noinline))
static void rt_spectrum_tap_forward(
    RTSpectrumTapContext *context,
    AVAudioPCMBuffer *buffer
) {
    float * const *channels = buffer.floatChannelData;
    AVAudioFrameCount frameLength = buffer.frameLength;
    if (channels == NULL || channels[0] == NULL || frameLength == 0) {
        return;
    }
    rt_spectrum_mailbox_submit(
        context->_submitContext,
        channels[0],
        (intptr_t)frameLength
    );
}

void rt_audio_node_install_spectrum_tap(
    void *nodePointer,
    uint32_t bus,
    uint32_t bufferSize,
    void *submitContext,
    void *lifetimeContext,
    RTSpectrumReleaseFunction releaseLifetime
) {
    AVAudioNode *node = (AVAudioNode *)nodePointer;
    RTSpectrumTapContext *context = [[RTSpectrumTapContext alloc]
        initWithSubmitContext:submitContext
        lifetimeContext:lifetimeContext
        releaseLifetime:releaseLifetime];
    [node installTapOnBus:bus
               bufferSize:bufferSize
                   format:nil
                    block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
        (void)when;
        rt_spectrum_tap_forward(context, buffer);
    }];
    [context release];
}
```

Configure the `RealtimeAtomics` target with `-fno-objc-arc` and link `AVFAudio`:

```swift
.target(
    name: "RealtimeAtomics",
    path: "Sources/RealtimeAtomics",
    publicHeadersPath: "include",
    cSettings: [.unsafeFlags(["-fno-objc-arc"])],
    linkerSettings: [.linkedFramework("AVFAudio")]
)
```

- [ ] **Step 4: Replace the Swift tap closure with a fixed raw entry**

Add the fixed, non-inlined raw entry in `SpectrumMailbox.swift` and make `SpectrumSubmission` store only its owner and context:

```swift
@_cdecl("rt_spectrum_mailbox_submit")
@inline(never)
func rtSpectrumMailboxSubmitC(
    _ context: UnsafeMutableRawPointer,
    _ samples: UnsafePointer<Float>,
    _ count: Int
) -> Bool {
    SpectrumMailbox.submit(
        context: context,
        samples: samples,
        count: count
    )
}
```

Add the storage-owner release function in `NoiseEngine.swift`:

```swift
private func releaseRetainedSpectrumSubmissionOwner(
    _ context: UnsafeMutableRawPointer
) {
    Unmanaged<AnyObject>.fromOpaque(context).release()
}
```

Replace `eq.installTap { ... }` with:

```swift
let lifetimeContext = Unmanaged.passRetained(
    submission.owner
).toOpaque()
rt_audio_node_install_spectrum_tap(
    Unmanaged.passUnretained(eq).toOpaque(),
    0,
    Self.spectrumBufferSize,
    submission.context,
    lifetimeContext,
    releaseRetainedSpectrumSubmissionOwner
)
```

The extra retained submission owner keeps `SpectrumMailbox` storage valid until AVAudioNode disposes the tap block. Analyzer shutdown remains idempotent, occurs after tap removal, and does not wait for copied-block disposal.

- [ ] **Step 5: Add lifetime assertions and run GREEN**

Extend `NoiseEngineSpectrumTapTests` so install/remove and reset assert this event order:

```swift
#expect(
    recorder.snapshot()
        == [.analyzerShutdown, .analyzerDeinit]
)
```

Run the focused spectrum lifecycle suite, full AudioEngine suite, TSan mailbox/analyzer suites, and Debug plus Release builds. Run `Scripts/audit-realtime-tap.sh` against both build roots. Run `Scripts/test-audit-realtime-tap.sh`, which builds normal arm64 Mach-O fixture roots and proves rejection of malformed Swift thunks, ownership, allocation, locks, dispatch, unexpected direct/tail/local calls, every indirect transfer including non-LR returns, unresolved transfers, configuration mismatches, and missing/ambiguous objects or symbols.

Expected: tests pass; no Swift AVAudioPCMBuffer thunk or dynamic submit thunk remains; the direct block → MRC forwarder → fixed raw entry → mailbox copy/publish → lock-free atomic chain contains only its exact allowlisted calls and control flow.

- [ ] **Step 6: Commit**

```bash
git add Packages/AudioEngine/Package.swift \
  Packages/AudioEngine/Sources/RealtimeAtomics \
  Packages/AudioEngine/Sources/AudioEngine/SpectrumAnalyzer.swift \
  Packages/AudioEngine/Sources/AudioEngine/SpectrumMailbox.swift \
  Packages/AudioEngine/Sources/AudioEngine/NoiseEngine.swift \
  Packages/AudioEngine/Tests/AudioEngineTests/NoiseEngineSpectrumTapTests.swift \
  Packages/AudioEngine/Tests/AudioEngineTests/SpectrumMailboxTests.swift \
  Scripts/audit-realtime-tap.sh \
  Scripts/test-audit-realtime-tap.sh \
  Scripts/Fixtures/RealtimeTapAudit
git commit -m "fix(audio): remove ARC from spectrum tap"
```

---

### Task 2: Bound Main-Actor Spectrum Delivery and Preserve Analysis Time

**Files:**

- Create: `Packages/AudioEngine/Sources/AudioEngine/SpectrumDeliveryGate.swift`
- Create: `Packages/AudioEngine/Tests/AudioEngineTests/SpectrumDeliveryGateTests.swift`
- Modify: `Packages/AudioEngine/Sources/AudioEngine/NoiseEngine.swift`
- Modify: `Packages/AudioEngine/Tests/AudioEngineTests/NoiseEngineSpectrumTapTests.swift`
- Modify: `Sculptor/Sources/PlaybackViewModel.swift`
- Modify: `Sculptor/Tests/PlaybackViewModelTests.swift`

**Interfaces:**

- Produces: `SpectrumDelivery(snapshot:generation:analyzedAt:)`.
- Produces: `SpectrumDeliveryGate.activate(generation:)`, `deactivate()`, and `submit(...)`.
- Changes: `NoiseEngine.onSpectrumSnapshot` to deliver both the snapshot and its original monotonic analysis instant.
- Guarantees: at most one scheduled main-actor drain and one replaceable pending value.

- [ ] **Step 1: Write RED delivery-gate tests**

Create tests with an injected scheduler that stores main-actor jobs instead of running them immediately:

```swift
@Test func blockedMainActorSchedulesOnceAndKeepsNewest() async {
    let scheduler = SpectrumMainJobRecorder()
    var received: [SpectrumDelivery] = []
    let gate = SpectrumDeliveryGate(
        schedule: scheduler.schedule,
        consume: { received.append($0) }
    )
    gate.activate(generation: 7)
    let clock = ContinuousClock()
    let firstAt = clock.now
    gate.submit(.zero, generation: 7, analyzedAt: firstAt)
    let newest = SpectrumSnapshot(
        bands: SIMD8<Float>(repeating: 0.8),
        rms: 0.7,
        peak: 0.9
    )
    let newestAt = clock.now
    gate.submit(newest, generation: 7, analyzedAt: newestAt)

    #expect(scheduler.count == 1)
    await scheduler.runNext()
    #expect(received.map(\.snapshot) == [newest])
    #expect(received.map(\.analyzedAt) == [newestAt])
}
```

Add tests that an old generation cannot replace a current pending value, deactivation clears pending work, and a submission arriving during consume schedules exactly one follow-up drain.

Run the new suite.

Expected: compilation fails because the gate types do not exist.

- [ ] **Step 2: Implement the newest-only gate**

Use `NSLock` only on the analysis worker/main delivery boundary, never in the audio tap:

```swift
struct SpectrumDelivery: Equatable, Sendable {
    let snapshot: SpectrumSnapshot
    let generation: UInt64
    let analyzedAt: ContinuousClock.Instant
}

final class SpectrumDeliveryGate: @unchecked Sendable {
    typealias Scheduler = @Sendable (
        @escaping @MainActor @Sendable () -> Void
    ) -> Void

    private let lock = NSLock()
    private let schedule: Scheduler
    private let consume: @MainActor @Sendable (SpectrumDelivery) -> Void
    private var activeGeneration: UInt64?
    private var pending: SpectrumDelivery?
    private var drainScheduled = false

    init(
        schedule: @escaping Scheduler = { job in
            Task { @MainActor in job() }
        },
        consume: @escaping @MainActor @Sendable (SpectrumDelivery) -> Void
    ) {
        self.schedule = schedule
        self.consume = consume
    }

    func activate(generation: UInt64) {
        lock.withLock {
            activeGeneration = generation
            pending = nil
        }
    }

    func deactivate() {
        lock.withLock {
            activeGeneration = nil
            pending = nil
        }
    }

    func submit(
        _ snapshot: SpectrumSnapshot,
        generation: UInt64,
        analyzedAt: ContinuousClock.Instant
    ) {
        let shouldSchedule = lock.withLock { () -> Bool in
            guard activeGeneration == generation else { return false }
            pending = SpectrumDelivery(
                snapshot: snapshot,
                generation: generation,
                analyzedAt: analyzedAt
            )
            guard !drainScheduled else { return false }
            drainScheduled = true
            return true
        }
        if shouldSchedule { scheduleDrain() }
    }

    private func scheduleDrain() {
        schedule { [weak self] in self?.drainOne() }
    }

    @MainActor
    private func drainOne() {
        let delivery = lock.withLock { () -> SpectrumDelivery? in
            defer { pending = nil }
            return pending
        }
        if let delivery { consume(delivery) }
        let shouldContinue = lock.withLock { () -> Bool in
            if pending != nil { return true }
            drainScheduled = false
            return false
        }
        if shouldContinue { scheduleDrain() }
    }
}
```

If implementation testing exposes a take/clear race, replace the `defer` body with an atomic local take under the same lock; do not weaken newest-only semantics.

- [ ] **Step 3: Wire generation and original timestamps through NoiseEngine**

Create one lazy gate owned by `NoiseEngine`. On installation call `activate(generation:)`; on removal/reset call `deactivate()`. The analyzer callback calls:

```swift
deliveryGate.submit(
    snapshot,
    generation: completedGeneration,
    analyzedAt: ContinuousClock().now
)
```

The gate's main-actor consumer calls `_acceptSpectrumSnapshot`. Change the callback contract to:

```swift
public var onSpectrumSnapshot: (
    @MainActor @Sendable (SpectrumSnapshot, ContinuousClock.Instant) -> Void
)?
```

In `PlaybackViewModel`, pass `analyzedAt` directly to `_ingestSpectrumSnapshot`; remove the code that stamps delayed callbacks with a fresh `clock.now`.

- [ ] **Step 4: Add adversarial NoiseEngine coverage and run GREEN**

In `NoiseEngineSpectrumTapTests`, submit at least 100 same-generation completions before allowing a scheduled main job to run, then assert one newest delivery. Submit a stale old-generation completion after reinstall and assert it cannot displace a current-generation pending value.

Run the gate suite, spectrum tap suite, full AudioEngine suite, and full Sculptor suite.

Expected: all tests pass and no per-frame `Task { @MainActor }` remains in the analyzer callback.

- [ ] **Step 5: Commit**

```bash
git add Packages/AudioEngine/Sources/AudioEngine/SpectrumDeliveryGate.swift \
  Packages/AudioEngine/Sources/AudioEngine/NoiseEngine.swift \
  Packages/AudioEngine/Tests/AudioEngineTests/SpectrumDeliveryGateTests.swift \
  Packages/AudioEngine/Tests/AudioEngineTests/NoiseEngineSpectrumTapTests.swift \
  Sculptor/Sources/PlaybackViewModel.swift \
  Sculptor/Tests/PlaybackViewModelTests.swift
git commit -m "fix(audio): bound spectrum delivery"
```

---

### Task 3: Serialize Audio-Session Commands Off Main and Pause After Reset

**Files:**

- Create: `Packages/AudioEngine/Sources/AudioEngine/AudioSessionCoordinator.swift`
- Create: `Packages/AudioEngine/Tests/AudioEngineTests/AudioSessionCoordinatorTests.swift`
- Modify: `Packages/AudioEngine/Sources/AudioEngine/NoiseEngine.swift`
- Modify: `Packages/AudioEngine/Tests/AudioEngineTests/NoiseEngineSessionTests.swift`
- Modify: `Packages/AudioEngine/Tests/AudioEngineTests/NoiseEngineInterruptionTests.swift`
- Modify: `Packages/AudioEngine/Tests/AudioEngineTests/NoiseEngineMediaResetTests.swift`
- Modify: `Packages/AudioEngine/Tests/AudioEngineTests/FadeTests.swift`
- Modify: `Sculptor/Sources/PlaybackViewModel.swift`
- Modify: `Sculptor/Tests/PlaybackViewModelTests.swift`

**Interfaces:**

- Produces: `AudioSessionInactivePolicy`, `AudioSessionCoordinating`, and `AudioSessionCoordinator`.
- Changes: `NoiseEngine.start()` becomes `async throws`.
- Preserves: both stop APIs update graph/tap/UI state synchronously; only AVAudioSession deactivation is queued.
- Produces: a cancellable PlaybackViewModel start request; a second toggle while starting means stop.

- [ ] **Step 1: Write coordinator RED tests**

Create deterministic injected operations and tests for:

```swift
@Test func activationRunsOffMainInCategoryThenActiveOrder() async throws
@Test func deactivationRunsOffMain() async
@Test func stopDuringBlockedActivationEndsInactive() async
@Test func rapidStopStartSkipsObsoleteDeactivation() async throws
@Test func queuedActivationSupersededBeforeExecutionNeverTouchesSession() async
@Test func systemManagedInterruptionSupersedesPendingActivation() async
@Test func cancelingCurrentActivationSchedulesCleanup() async
@Test func cancellationBeforeActivationBeginsNeverRegistersActiveIntent() async
@Test func systemManagedLateActivationNeverExplicitlyDeactivates() async
@Test func staleActivationFailureBecomesCancellationError() async
@Test func requestInactiveReturnsWhileSessionOperationIsBlocked() async
```

Each test records thread identity and exact operations. Cover both a queued obsolete deactivation and a deactivation that has already begun: the rapid sequence must end exactly in `.active`, and no deactivate may occur after the winning activation. Also prove that canceling an older activation after a newer activation exists cannot deactivate the newer one, and distinguish current real failures from stale failures.

Run the new suite.

Expected: compilation fails because coordinator types do not exist.

- [ ] **Step 2: Implement one serial coordinator with command generations**

Define:

```swift
enum AudioSessionInactivePolicy: Sendable {
    case deactivate
    case systemManaged
}

protocol AudioSessionCoordinating: Sendable {
    func activate() async throws
    func requestInactive(_ policy: AudioSessionInactivePolicy)
    func waitUntilIdle() async
}
```

`AudioSessionCoordinator` must:

- expose one process-wide live coordinator because `AVAudioSession` is a singleton; tests may construct isolated coordinators with injected operations;
- run injected `setCategory(.playback, .default)` and `setActive(Bool)` closures on that coordinator's dedicated serial `DispatchQueue`;
- allocate a monotonically increasing command ID synchronously under `NSLock`;
- store the locked desired state as `.active(generation)` or `.inactive(generation, policy)` and keep applied state queue-confined; never hold the lock while an AVAudioSession operation runs;
- check whether activation is current before category, between category and activation, and after activation;
- return `CancellationError` for every superseded activation, including a stale operation that throws a real session error;
- skip an obsolete deactivation when a later activation is current;
- if an activation finishes after the desired state became `.inactive(.deactivate)`, deactivate on the same serial queue before completing cancellation;
- if an activation finishes after the desired state became `.inactive(.systemManaged)`, never call `setActive(false)` because the system owns interruption deactivation;
- never let cancellation of an older activation enqueue a deactivate behind a newer activation;
- expose `waitUntilIdle()` only for deterministic tests and shutdown verification, implemented by asynchronously enqueuing a continuation rather than `queue.sync` from main.

Use live operations:

```swift
let session = AVAudioSession.sharedInstance()
try session.setCategory(.playback, mode: .default)
try session.setActive(active)
```

These closures execute only on the coordinator queue.

- [ ] **Step 3: Make NoiseEngine start asynchronous and generation-safe**

Inject `any AudioSessionCoordinating` through the internal initializer; public initializers use `AudioSessionCoordinator.shared`. Add `playbackGeneration` and public-read `isPlaybackRequested`.

`start()` must:

```swift
public func start() async throws {
    try Task.checkCancellation()
    guard !isPlaying else { return }

    if isFading, engine.isRunning {
        fadeTask?.cancel()
        fadeTask = nil
        isFading = false
        playbackGeneration &+= 1
        isPlaybackRequested = true
        engine.mainMixerNode.outputVolume = masterVolume
        isPlaying = true
        if spectrumAnalysisEnabled { _installSpectrumTap() }
        return
    }

    fadeTask?.cancel()
    fadeTask = nil
    isFading = false
    playbackGeneration &+= 1
    let generation = playbackGeneration
    isPlaybackRequested = true

    do {
        try await audioSessionCoordinator.activate()
    } catch {
        guard generation == playbackGeneration else {
            throw CancellationError()
        }
        if isPlaybackRequested {
            isPlaybackRequested = false
        }
        throw error
    }

    guard !Task.isCancelled,
          generation == playbackGeneration,
          isPlaybackRequested else {
        if generation == playbackGeneration, isPlaybackRequested {
            isPlaybackRequested = false
            audioSessionCoordinator.requestInactive(.deactivate)
        }
        throw CancellationError()
    }
    do {
        engine.mainMixerNode.outputVolume = masterVolume
        if !engine.isRunning { try engine.start() }
        isPlaying = true
        if spectrumAnalysisEnabled { _installSpectrumTap() }
    } catch {
        isPlaybackRequested = false
        audioSessionCoordinator.requestInactive(.deactivate)
        throw error
    }
}
```

Both stop paths invalidate `playbackGeneration` and set `isPlaybackRequested = false` before removing the tap/stopping the engine. `finishStop` calls `requestInactive(.deactivate)` after `engine.stop()`, or `.systemManaged` for interruption handling. An immediate play during an active fade uses the synchronous fast path above because the graph and session are still active; it restores mixer volume and cancels the old fade so that task can never later stop or deactivate the restarted playback.

- [ ] **Step 4: Update interruption and media-reset policy**

Make `_applyInterruption` async so `.resume` can `try? await start()`. Notification tasks await it. Track an interruption epoch plus a single consumable resume token. `.began` captures `isPlaying || isPlaybackRequested`, preserves an existing token across nested begin notifications, and stops with `.systemManaged`. `.ended` may consume only the matching token once. Explicit stop, route loss, or media reset clears the token so a delayed ended notification cannot restart playback.

On media reset:

```swift
func _recoverFromMediaServicesReset() {
    playbackGeneration &+= 1
    isPlaybackRequested = false
    // invalidate the interruption epoch and clear all resume intent
    // cancel fade, discard old analyzer without messaging invalid EQ,
    // rebuild graph, restore gain shadows
    isPlaying = false
    audioSessionCoordinator.requestInactive(.systemManaged)
}
```

Delete automatic `start()` after reset. Add a test that forces prior playback and pending interruption-resume state, recovers, and proves playback remains paused through a later interruption-ended notification until a new explicit `await start()`. Also cover reset racing a blocked activation.

- [ ] **Step 5: Make PlaybackViewModel own the cancellable start request**

Keep `togglePlay()` synchronous for SwiftUI. Store `startTask` and a monotonically increasing request ID. When stopped and not starting, create a main-actor task that awaits `engine.start()`. When playing or starting, cancel the task and call `engine.stop(fadeDuration:)`. Ignore `CancellationError`; publish only a real error from the still-current request. Treat `isPlaying || startTask != nil || engine.isPlaybackRequested` as effective playback intent. A second toggle, remote pause, sleep expiry, and every other stop source must cancel and invalidate the pending task before stopping the engine; remote play/pause guards must use effective intent.

Add tests:

```swift
@Test func secondToggleWhileStartingCancelsWithoutError() async
@Test func remotePauseWhileStartingCancelsWithoutError() async
@Test func sleepExpiryWhileStartingCancelsWithoutError() async
@Test func staleStartFailureCannotOverwriteNewerState() async
@Test func activationFailureLeavesRequestedAndPlayingFalse() async
@Test func immediateRestartDuringFadeKeepsGraphAndSessionActive() async
```

- [ ] **Step 6: Run GREEN and negative-warning audit**

Run coordinator, session, interruption, media-reset, fade, and PlaybackViewModel suites; then full AudioEngine and Sculptor suites. Search every test log for:

```bash
! rg -i 'AVAudioSession Hang Risk|UI unresponsiveness' /tmp/sculptor-ripple-session-*.log
```

Expected: all tests pass; category/activation/deactivation test closures report non-main execution; no hang-risk diagnostic appears.

- [ ] **Step 7: Commit**

```bash
git add Packages/AudioEngine/Sources/AudioEngine/AudioSessionCoordinator.swift \
  Packages/AudioEngine/Sources/AudioEngine/NoiseEngine.swift \
  Packages/AudioEngine/Tests/AudioEngineTests/AudioSessionCoordinatorTests.swift \
  Packages/AudioEngine/Tests/AudioEngineTests/NoiseEngineSessionTests.swift \
  Packages/AudioEngine/Tests/AudioEngineTests/NoiseEngineInterruptionTests.swift \
  Packages/AudioEngine/Tests/AudioEngineTests/NoiseEngineMediaResetTests.swift \
  Packages/AudioEngine/Tests/AudioEngineTests/FadeTests.swift \
  Sculptor/Sources/PlaybackViewModel.swift \
  Sculptor/Tests/PlaybackViewModelTests.swift
git commit -m "fix(audio): move session work off main"
```

---

### Task 4: Re-run the Complete Production Gate

**Files:**

- Modify: `docs/superpowers/specs/2026-07-12-audio-reactive-metal-ripple-design.md`
- Modify: `.superpowers/sdd/task-10-report.md` (ignored evidence only)
- Verify: all files changed by Tasks 1-3

**Interfaces:**

- Consumes: MRC tap bridge, delivery gate, audio-session coordinator, paused reset policy.
- Produces: canonical, sanitizer, object-code, runtime, and repository evidence for the hardened head.

- [ ] **Step 1: Update the design record**

Document the MRC bridge lifetime owner, bounded main delivery/timestamp semantics, serialized session commands, and paused media-reset behavior. Remove claims that the old Swift block boundary or direct main-actor delivery was ARC-free/bounded.

- [ ] **Step 2: Run the canonical suite**

Cleanly boot the available dedicated simulator and run:

```bash
TMPDIR=/tmp SIM="iPhone 17 Pro" Scripts/test-all.sh \
  > /tmp/sculptor-ripple-hardened-full-suite.log 2>&1
```

Expected: AudioEngine, DesignSystem, and Sculptor each report `TEST SUCCEEDED`; the command exits 0; no AVAudioSession hang-risk diagnostic occurs.

- [ ] **Step 3: Run sanitizers and object audits**

Run mailbox, analyzer, delivery-gate, tap-lifecycle, and session-coordinator stress suites under TSan. Run tap-vs-remove/reset lifetime stress under ASan. Build Debug and Release arm64 artifacts and run `Scripts/audit-realtime-tap.sh` on both.

Expected: no sanitizer finding; no Swift AVAudioPCMBuffer tap thunk; no retain/release in the MRC callback entry/forwarder.

- [ ] **Step 4: Rebuild and smoke the app**

Generate with Tuist, build to `/tmp/SculptorRippleHardened`, install/launch, capture two paused Home screenshots, and audit runtime logs for shader, crash, Metal, AVAudioSession hang-risk, and assertion diagnostics.

Expected: contours are nonempty and drift; runtime diagnostic search has zero matches.

- [ ] **Step 5: Run repository audit and report limitations**

Run `git diff --check`, legacy-symbol audit, new-symbol audit, and `git status`. Report live tap interactions and physical-device Instruments profiling as outstanding unless actually completed; do not turn test coverage into a live-runtime claim.

- [ ] **Step 6: Commit documentation**

```bash
git add docs/superpowers/specs/2026-07-12-audio-reactive-metal-ripple-design.md
git commit -m "docs: record hardened audio pipeline"
```

---

## Deferred Device-Only Acceptance

The following cannot be marked passed without attached hardware: 60-second Metal System Trace and Time Profiler, audio-underrun inspection, real 60/30 fps cadence, per-tap activity inspection, and confirmation of the single procedural Metal pass. Live play/stop, eight-band, Sculpt/Presets, NOISE/PHONE, lifecycle, Low Power, and Reduce Motion interaction also remains a separate manual/UI-automation gate when the required driver is available.
