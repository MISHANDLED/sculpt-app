import SwiftUI
import AudioEngine
import DesignSystem

/// Horizontal row of preset chips, shared by Now Playing and Sculpt. Selection
/// and tap routing go through the shared PlaybackViewModel.
struct PresetChipsRow: View {
    @ObservedObject var vm: PlaybackViewModel
    let customPresets: [CustomPreset]

    private let presets: [(NoisePreset, String)] = [
        (.white, "White"), (.pink, "Pink"), (.brown, "Brown"),
        (.grey, "Grey"), (.speechBlocker, "Speech blocker")
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DockSpacing.sm) {
                ForEach(presets, id: \.0) { preset, title in
                    PresetChip(title: title, isSelected: !vm.isEdited && vm.selection == .builtin(preset)) {
                        vm.select(preset)
                    }
                }
                ForEach(customPresets) { preset in
                    PresetChip(
                        title: preset.name,
                        isSelected: !vm.isEdited
                            && vm.selection == .custom(preset.id)
                    ) {
                        vm.applyCustom(
                            id: preset.id,
                            gains: preset.gains
                        )
                    }
                }
            }
        }
    }
}

#Preview {
    PresetChipsRow(vm: PlaybackViewModel(), customPresets: [])
        .padding()
        .background(DockColor.background)
}
