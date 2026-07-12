import AudioEngine
import CoreGraphics
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

    @Test func shaderTimeRemainsMonotonicAcrossLegacyBoundary() {
        let before: Float = 167.999
        let boundary: Float = 168
        let after: Float = 168.001
        let distant: Float = 10_000

        #expect(LivingContoursTiming.shaderTime(before) == before)
        #expect(LivingContoursTiming.shaderTime(boundary) == boundary)
        #expect(LivingContoursTiming.shaderTime(after) == after)
        #expect(LivingContoursTiming.shaderTime(distant) == distant)
        #expect(
            LivingContoursTiming.shaderTime(before)
                < LivingContoursTiming.shaderTime(boundary)
        )
        #expect(
            LivingContoursTiming.shaderTime(boundary)
                < LivingContoursTiming.shaderTime(after)
        )
    }

    @Test func shaderTimeSanitizesInvalidValues() {
        #expect(LivingContoursTiming.shaderTime(-0.001) == 0)
        #expect(LivingContoursTiming.shaderTime(.nan) == 0)
        #expect(LivingContoursTiming.shaderTime(.infinity) == 0)
        #expect(LivingContoursTiming.shaderTime(-.infinity) == 0)
    }

    @Test func payloadPreservesShaderInputPacking() {
        let uniforms = RippleUniforms(
            bandsLow: SIMD4<Float>(0.06, 0.125, 0.25, 0.5),
            bandsHigh: SIMD4<Float>(1, 0.2, 0.4, 0.8),
            rms: 0.31,
            peak: 0.47,
            audioResponseScale: 0.63,
            motionScale: 0.72,
            detailScale: 0.81,
            elapsedTime: 168.25
        )

        let payload = LivingContoursPayload(
            size: CGSize(width: 320, height: 640),
            uniforms: uniforms
        )

        #expect(payload.canvasSize == CGSize(width: 320, height: 640))
        #expect(payload.elapsedTime == 168.25)
        #expect(payload.bandsLow == uniforms.bandsLow)
        #expect(payload.bandsHigh == uniforms.bandsHigh)
        #expect(payload.rms == uniforms.rms)
        #expect(payload.peak == uniforms.peak)
        #expect(payload.audioResponseScale == uniforms.audioResponseScale)
        #expect(payload.motionScale == uniforms.motionScale)
        #expect(payload.detailScale == uniforms.detailScale)
    }
}
