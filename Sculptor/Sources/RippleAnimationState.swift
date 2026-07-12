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
        let fractional = Float(
            Double(components.attoseconds) / 1_000_000_000_000_000_000
        )
        return max(0, whole + fractional)
    }

    private static func clamp(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }
}
