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
        func unpack(_ value: LivingContoursTime) -> Double {
            Double(value.phase.x) + Double(value.phase.y)
        }

        let before = unpack(LivingContoursTiming.shaderTime(167.999))
        let boundary = unpack(LivingContoursTiming.shaderTime(168))
        let after = unpack(LivingContoursTiming.shaderTime(168.001))
        let distant = unpack(LivingContoursTiming.shaderTime(10_000))

        #expect(abs(before - 167.999) < 0.000_001)
        #expect(boundary == 168)
        #expect(abs(after - 168.001) < 0.000_001)
        #expect(distant == 10_000)
        #expect(before < boundary)
        #expect(boundary < after)
    }

    @Test func shaderTimePreservesLongUptimePrecision() {
        let before = LivingContoursTiming.shaderTime(131_072)
        let after = LivingContoursTiming.shaderTime(131_072.001)
        let unpackedBefore = Double(before.phase.x) + Double(before.phase.y)
        let unpackedAfter = Double(after.phase.x) + Double(after.phase.y)

        #expect(abs((unpackedAfter - unpackedBefore) - 0.001) < 0.000_001)
    }

    @Test func shaderTimeKeepsSixtyFPSNoiseMotionAfterLongUptime() {
        func noiseOffset(
            _ time: LivingContoursTime,
            index: Int
        ) -> Double {
            Double(time.noiseCell[index]) + Double(time.noiseLocal[index])
        }

        let starts = [262_144.25, 524_288.25, 1_000_000.25]
        let rates = [0.018, -0.014]
        for start in starts {
            let initial = LivingContoursTiming.shaderTime(start)
            for step in 0..<12 {
                let before = LivingContoursTiming.shaderTime(
                    start + Double(step) / 60
                )
                let after = LivingContoursTiming.shaderTime(
                    start + Double(step + 1) / 60
                )

                for index in 0..<2 {
                    let delta = noiseOffset(after, index: index)
                        - noiseOffset(before, index: index)
                    #expect(abs(delta - rates[index] / 60) < 0.000_000_2)
                }
            }

            let final = LivingContoursTiming.shaderTime(start + 12.0 / 60.0)
            for index in 0..<2 {
                let accumulated = noiseOffset(final, index: index)
                    - noiseOffset(initial, index: index)
                #expect(abs(accumulated - rates[index] * 12 / 60) < 0.000_001)
            }
        }
    }

    @Test func shaderNoiseTimeCarriesAcrossChunkBoundary() {
        func noiseOffset(
            _ time: LivingContoursTime,
            index: Int
        ) -> Double {
            Double(time.noiseCell[index]) + Double(time.noiseLocal[index])
        }

        let before = LivingContoursTiming.shaderTime(499.999)
        let after = LivingContoursTiming.shaderTime(500.001)
        let rates = [0.018, -0.014]

        #expect(before.noiseCell == .zero)
        #expect(after.noiseCell == SIMD2<Float>(9, -7))
        for index in 0..<2 {
            let delta = noiseOffset(after, index: index)
                - noiseOffset(before, index: index)
            #expect(abs(delta - 0.002 * rates[index]) < 0.000_001)
        }
    }

    @Test func shaderPhaseIsContinuousAcrossCoarseFloatBoundary() {
        func phase(_ time: LivingContoursTime, rate: Float) -> Float {
            let period = 2 * Float.pi / abs(rate)
            let boundedCoarse = time.phase.x.truncatingRemainder(
                dividingBy: period
            )
            return (time.phase.y * rate).addingProduct(boundedCoarse, rate)
        }

        let lower: Float = 131_072
        let upper = lower.nextUp
        let boundary = (Double(lower) + Double(upper)) / 2
        let before = LivingContoursTiming.shaderTime(boundary - 0.001)
        let after = LivingContoursTiming.shaderTime(boundary + 0.001)
        let rate: Float = 0.18

        #expect(before.phase.x == lower)
        #expect(after.phase.x == upper)
        #expect(before.phase.y > 0)
        #expect(after.phase.y < 0)
        #expect(
            abs((phase(after, rate: rate) - phase(before, rate: rate))
                - 0.002 * rate) < 0.000_001
        )
    }

    @Test func shaderTimeSanitizesInvalidValues() {
        #expect(LivingContoursTiming.shaderTime(-0.001) == .zero)
        #expect(LivingContoursTiming.shaderTime(.nan) == .zero)
        #expect(LivingContoursTiming.shaderTime(.infinity) == .zero)
        #expect(LivingContoursTiming.shaderTime(-.infinity) == .zero)
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
        #expect(payload.elapsedTime.phase == SIMD2<Float>(168.25, 0))
        #expect(payload.elapsedTime.noiseCell == .zero)
        #expect(
            abs(payload.elapsedTime.noiseLocal.x - 3.0285) < 0.000_001
        )
        #expect(
            abs(payload.elapsedTime.noiseLocal.y + 2.3555) < 0.000_001
        )
        #expect(payload.bandsLow == uniforms.bandsLow)
        #expect(payload.bandsHigh == uniforms.bandsHigh)
        #expect(payload.rms == uniforms.rms)
        #expect(payload.peak == uniforms.peak)
        #expect(payload.audioResponseScale == uniforms.audioResponseScale)
        #expect(payload.motionScale == uniforms.motionScale)
        #expect(payload.detailScale == uniforms.detailScale)
    }
}
