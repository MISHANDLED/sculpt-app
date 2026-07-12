import AudioEngine
import Combine
import DesignSystem
import Foundation
import SwiftUI

struct LivingContoursTime: Equatable, Sendable {
    let phase: SIMD2<Float>
    let noiseCell: SIMD2<Float>
    let noiseLocal: SIMD2<Float>

    static let zero = LivingContoursTime(
        phase: .zero,
        noiseCell: .zero,
        noiseLocal: .zero
    )
}

enum LivingContoursTiming {
    private static let noiseChunkSeconds = 500.0

    static func shaderTime(_ elapsedTime: Double) -> LivingContoursTime {
        guard elapsedTime.isFinite else { return .zero }
        let sanitized = max(0, elapsedTime)
        let coarse = Float(sanitized)
        guard coarse.isFinite else { return .zero }
        let fine = Float(sanitized - Double(coarse))

        var chunk = floor(sanitized / noiseChunkSeconds)
        var remainder = sanitized.addingProduct(
            -chunk,
            noiseChunkSeconds
        )
        if remainder < 0 {
            chunk -= 1
            remainder += noiseChunkSeconds
        } else if remainder >= noiseChunkSeconds {
            chunk += 1
            remainder -= noiseChunkSeconds
        }

        let noiseCell = SIMD2<Float>(
            Float(chunk * 9),
            Float(chunk * -7)
        )
        let noiseLocal = SIMD2<Float>(
            Float(remainder * 0.018),
            Float(remainder * -0.014)
        )
        guard noiseCell.x.isFinite, noiseCell.y.isFinite,
              noiseLocal.x.isFinite, noiseLocal.y.isFinite else {
            return .zero
        }
        return LivingContoursTime(
            phase: SIMD2<Float>(coarse, fine),
            noiseCell: noiseCell,
            noiseLocal: noiseLocal
        )
    }
}

struct LivingContoursPayload: Equatable {
    let canvasSize: CGSize
    let elapsedTime: LivingContoursTime
    let bandsLow: SIMD4<Float>
    let bandsHigh: SIMD4<Float>
    let rms: Float
    let peak: Float
    let audioResponseScale: Float
    let motionScale: Float
    let detailScale: Float

    init(size: CGSize, uniforms: RippleUniforms) {
        canvasSize = size
        elapsedTime = LivingContoursTiming.shaderTime(uniforms.elapsedTime)
        bandsLow = uniforms.bandsLow
        bandsHigh = uniforms.bandsHigh
        rms = uniforms.rms
        peak = uniforms.peak
        audioResponseScale = uniforms.audioResponseScale
        motionScale = uniforms.motionScale
        detailScale = uniforms.detailScale
    }
}

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
            // TimelineView supplies the tick; sample its monotonic instant
            // once and let GeometryReader capture the immutable uniforms.
            let tickInstant = clock.now
            let uniforms = animationState.uniforms(at: tickInstant)
            GeometryReader { proxy in
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
        let payload = LivingContoursPayload(size: size, uniforms: uniforms)
        return ShaderLibrary.livingContours(
            .float2(payload.canvasSize),
            .float2(
                CGSize(
                    width: CGFloat(payload.elapsedTime.phase.x),
                    height: CGFloat(payload.elapsedTime.phase.y)
                )
            ),
            .float2(
                CGSize(
                    width: CGFloat(payload.elapsedTime.noiseCell.x),
                    height: CGFloat(payload.elapsedTime.noiseCell.y)
                )
            ),
            .float2(
                CGSize(
                    width: CGFloat(payload.elapsedTime.noiseLocal.x),
                    height: CGFloat(payload.elapsedTime.noiseLocal.y)
                )
            ),
            .float4(
                payload.bandsLow.x,
                payload.bandsLow.y,
                payload.bandsLow.z,
                payload.bandsLow.w
            ),
            .float4(
                payload.bandsHigh.x,
                payload.bandsHigh.y,
                payload.bandsHigh.z,
                payload.bandsHigh.w
            ),
            .float(payload.rms),
            .float(payload.peak),
            .float(payload.audioResponseScale),
            .float(payload.motionScale),
            .float(payload.detailScale),
            .color(DockColor.accent)
        )
    }
}
