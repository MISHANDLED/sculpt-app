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
