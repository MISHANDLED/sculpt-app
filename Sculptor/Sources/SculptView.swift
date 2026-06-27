import SwiftUI
import AudioEngine
import DesignSystem

struct SculptView: View {
    @StateObject private var vm = PlaybackViewModel()

    private let presets: [(NoisePreset, String)] = [
        (.white, "White"), (.pink, "Pink"), (.brown, "Brown"),
        (.grey, "Grey"), (.speechBlocker, "Speech blocker")
    ]

    var body: some View {
        ZStack {
            DockColor.background.ignoresSafeArea()

            VStack(spacing: DockSpacing.xl) {
                Text("Sculpt")
                    .font(DockType.font(24, .semibold))
                    .foregroundStyle(DockColor.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                DockCard {
                    HStack(alignment: .bottom, spacing: DockSpacing.xs) {
                        ForEach(0..<8, id: \.self) { i in
                            VStack(spacing: DockSpacing.sm) {
                                BandSlider(
                                    value: Binding(
                                        get: { vm.gains[i] },
                                        set: { vm.setGain(band: i, dB: $0) }
                                    ),
                                    range: -24...12
                                )
                                .frame(maxWidth: .infinity)
                                .frame(height: 200)
                                Text(label(vm.frequencies[i]))
                                    .font(DockType.font(10, .medium))
                                    .foregroundStyle(DockColor.textTertiary)
                                    .fixedSize()
                            }
                        }
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DockSpacing.sm) {
                        ForEach(presets, id: \.0) { preset, title in
                            PresetChip(title: title, isSelected: vm.selectedPreset == preset) {
                                vm.select(preset)
                            }
                        }
                    }
                }

                DockButton(title: vm.isPlaying ? "Pause" : "Play") { vm.togglePlay() }

                if let err = vm.errorText {
                    Text(err).font(DockType.font(12)).foregroundStyle(.red)
                }

                Spacer()
            }
            .padding(DockSpacing.xl)
        }
    }

    private func label(_ f: Float) -> String {
        f >= 1000 ? "\(Int(f / 1000))k" : "\(Int(f))"
    }
}

#Preview { SculptView() }
