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
