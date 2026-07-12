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

    private func expectEnvelopeAndTime(
        _ actual: RippleUniforms,
        equals expected: RippleUniforms,
        tolerance: Float = 0.000001
    ) {
        #expect(abs(actual.bandsLow.x - expected.bandsLow.x) < tolerance)
        #expect(abs(actual.bandsLow.y - expected.bandsLow.y) < tolerance)
        #expect(abs(actual.bandsLow.z - expected.bandsLow.z) < tolerance)
        #expect(abs(actual.bandsLow.w - expected.bandsLow.w) < tolerance)
        #expect(abs(actual.bandsHigh.x - expected.bandsHigh.x) < tolerance)
        #expect(abs(actual.bandsHigh.y - expected.bandsHigh.y) < tolerance)
        #expect(abs(actual.bandsHigh.z - expected.bandsHigh.z) < tolerance)
        #expect(abs(actual.bandsHigh.w - expected.bandsHigh.w) < tolerance)
        #expect(abs(actual.rms - expected.rms) < tolerance)
        #expect(abs(actual.peak - expected.peak) < tolerance)
        #expect(
            abs(actual.elapsedTime - expected.elapsedTime) < Double(tolerance)
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

    @Test func retargetPreservesEveryEnvelopeChannelAndShaderTime() {
        let start = clock.now
        let retargetTime = start.advanced(by: .milliseconds(60))
        let bands = SIMD8<Float>(0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8)
        var state = RippleAnimationState(at: start)
        state.retarget(
            to: input(
                snapshot: SpectrumSnapshot(
                    bands: bands,
                    rms: 0.55,
                    peak: 0.9
                ),
                receivedAt: start
            ),
            at: start
        )
        let before = state.uniforms(at: retargetTime)
        state.retarget(
            to: input(snapshot: snapshot(0.1), receivedAt: retargetTime),
            at: retargetTime
        )
        let after = state.uniforms(at: retargetTime)
        expectEnvelopeAndTime(after, equals: before)
    }

    @Test func stalePhaseRetargetPreservesEnvelopeAndShaderTime() {
        let start = clock.now
        let retargetTime = start.advanced(by: .milliseconds(500))
        let bands = SIMD8<Float>(0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8)
        var state = RippleAnimationState(at: start)
        state.retarget(
            to: input(
                snapshot: SpectrumSnapshot(
                    bands: bands,
                    rms: 0.7,
                    peak: 0.9
                ),
                receivedAt: start
            ),
            at: start
        )
        let before = state.uniforms(at: retargetTime)

        state.retarget(
            to: input(snapshot: snapshot(0.2), receivedAt: retargetTime),
            at: retargetTime
        )

        let after = state.uniforms(at: retargetTime)
        expectEnvelopeAndTime(after, equals: before)
    }

    @Test func reversedRetargetKeepsAnchorAndShaderTimeMonotonic() {
        let start = clock.now
        let forward = start.advanced(by: .milliseconds(200))
        let backward = start.advanced(by: .milliseconds(100))
        let later = start.advanced(by: .milliseconds(300))
        var state = RippleAnimationState(at: start)
        state.retarget(
            to: input(snapshot: snapshot(1), receivedAt: start),
            at: start
        )
        state.retarget(
            to: input(snapshot: snapshot(0.8), receivedAt: forward),
            at: forward
        )
        let beforeReverse = state.uniforms(at: forward)

        state.retarget(
            to: input(snapshot: snapshot(0.2), receivedAt: forward),
            at: backward
        )

        let afterReverse = state.uniforms(at: forward)
        expectEnvelopeAndTime(afterReverse, equals: beforeReverse)
        #expect(abs(state.uniforms(at: later).elapsedTime - 0.3) < 0.000001)
    }

    @Test func shaderTimeRetainsMillisecondResolutionAfterLongUptime() {
        let start = clock.now
        let longUptime = start.advanced(by: .seconds(131_072))
        let nextMillisecond = longUptime.advanced(by: .milliseconds(1))
        var state = RippleAnimationState(at: start)
        state.retarget(
            to: input(snapshot: .zero, receivedAt: nil),
            at: start
        )

        let before = state.uniforms(at: longUptime).elapsedTime
        let after = state.uniforms(at: nextMillisecond).elapsedTime

        #expect(abs((after - before) - 0.001) < 0.000_001)
    }

    @Test func staleSpectrumReleasesAfter350Milliseconds() {
        let start = clock.now
        let immediatelyBefore = start.advanced(by: .milliseconds(349))
        let staleBoundary = start.advanced(by: .milliseconds(350))
        let immediatelyAfter = start.advanced(by: .milliseconds(351))
        var state = RippleAnimationState(at: start)
        state.retarget(
            to: input(snapshot: snapshot(1), receivedAt: start),
            at: start
        )
        let before = state.uniforms(at: immediatelyBefore)
        let atBoundary = state.uniforms(at: staleBoundary)
        let after = state.uniforms(at: immediatelyAfter)
        let released = state.uniforms(
            at: staleBoundary.advanced(by: .milliseconds(450))
        )

        #expect(abs(before.rms - 0.9454334) < 0.00001)
        #expect(abs(atBoundary.rms - 0.94588625) < 0.00001)
        #expect(abs(after.rms - 0.9437866) < 0.00001)
        #expect(abs(after.peak - 0.94211024) < 0.00001)
        #expect(before.rms < atBoundary.rms)
        #expect(after.rms < atBoundary.rms)
        #expect(after.peak < atBoundary.peak)
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

    @Test func masterVolumeSanitizationDoesNotChangeEnvelopes() {
        let start = clock.now
        let sample = SpectrumSnapshot(
            bands: SIMD8<Float>(0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8),
            rms: 0.6,
            peak: 0.9
        )
        let queryTime = start.advanced(by: .milliseconds(120))
        var baselineState = RippleAnimationState(at: start)
        baselineState.retarget(
            to: input(
                snapshot: sample,
                receivedAt: start,
                masterVolume: 1
            ),
            at: start
        )
        let baseline = baselineState.uniforms(at: queryTime)
        let cases: [(volume: Float, expected: Float)] = [
            (-1, 0),
            (2, 1),
            (.nan, 0),
            (.infinity, 0),
            (-.infinity, 0),
        ]

        for volumeCase in cases {
            var state = RippleAnimationState(at: start)
            state.retarget(
                to: input(
                    snapshot: sample,
                    receivedAt: start,
                    masterVolume: volumeCase.volume
                ),
                at: start
            )
            let uniforms = state.uniforms(at: queryTime)

            #expect(uniforms.audioResponseScale == volumeCase.expected)
            expectEnvelopeAndTime(uniforms, equals: baseline)
        }
    }

    @Test func pauseFromAudibleStateReleasesAudioAndPreservesDrift() {
        let start = clock.now
        let pauseAt = start.advanced(by: .milliseconds(120))
        var state = RippleAnimationState(at: start)
        state.retarget(
            to: input(snapshot: snapshot(1), receivedAt: start),
            at: start
        )
        let audible = state.uniforms(at: pauseAt)
        state.retarget(
            to: input(snapshot: .zero, receivedAt: nil, isPlaying: false),
            at: pauseAt
        )
        let paused = state.uniforms(at: pauseAt)
        let peakReleased = state.uniforms(
            at: pauseAt.advanced(by: .milliseconds(250))
        )
        let released = state.uniforms(
            at: pauseAt.advanced(by: .milliseconds(450))
        )

        expectEnvelopeAndTime(paused, equals: audible)
        #expect(abs(released.bandsLow.x - audible.bandsLow.x * 0.36787945) < 0.0001)
        #expect(abs(released.bandsHigh.w - audible.bandsHigh.w * 0.36787945) < 0.0001)
        #expect(abs(released.rms - audible.rms * 0.36787945) < 0.0001)
        #expect(abs(peakReleased.peak - audible.peak * 0.36787945) < 0.0001)
        #expect(abs(released.elapsedTime - 0.57) < 0.0001)
        #expect(released.audioResponseScale == 1)
    }

    @Test func inactiveStateAgesEnvelopeAndReactivationResumesFrozenTime() {
        let start = clock.now
        let inactiveAt = start.advanced(by: .milliseconds(120))
        let reactivateAt = inactiveAt.advanced(by: .milliseconds(450))
        var state = RippleAnimationState(at: start)
        state.retarget(
            to: input(snapshot: snapshot(1), receivedAt: start),
            at: start
        )
        let active = state.uniforms(at: inactiveAt)
        state.retarget(
            to: input(
                snapshot: .zero,
                receivedAt: nil,
                isActive: false
            ),
            at: inactiveAt
        )
        let becameInactive = state.uniforms(at: inactiveAt)
        let aged = state.uniforms(at: reactivateAt)

        expectEnvelopeAndTime(becameInactive, equals: active)
        #expect(abs(aged.rms - active.rms * 0.36787945) < 0.0001)
        #expect(abs(aged.elapsedTime - 0.12) < 0.0001)

        state.retarget(
            to: input(snapshot: snapshot(1), receivedAt: reactivateAt),
            at: reactivateAt
        )
        let reactivated = state.uniforms(at: reactivateAt)
        expectEnvelopeAndTime(reactivated, equals: aged)

        let resumed = state.uniforms(
            at: reactivateAt.advanced(by: .milliseconds(120))
        )
        #expect(resumed.rms > reactivated.rms)
        #expect(abs(resumed.elapsedTime - 0.24) < 0.0001)
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
