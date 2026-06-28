import SwiftUI
import SwiftData
import AudioEngine
import DesignSystem

struct PresetsView: View {
    @ObservedObject var vm: PlaybackViewModel
    @Environment(\.modelContext) private var context
    @Query(sort: \CustomPreset.sortIndex) private var customPresets: [CustomPreset]

    private let builtins: [(NoisePreset, String, String)] = [
        (.brown, "Brown", "Deep, low-end rumble"),
        (.pink, "Pink", "Balanced, natural tilt"),
        (.white, "White", "Flat across the spectrum"),
        (.grey, "Grey", "Equal-loudness shaped"),
        (.speechBlocker, "Speech blocker", "Masks nearby conversation")
    ]

    var body: some View {
        ZStack {
            DockColor.background.ignoresSafeArea()
            List {
                Section {
                    ForEach(builtins, id: \.0) { preset, title, subtitle in
                        PresetRow(title: title, subtitle: subtitle, gains: preset.gains,
                                  isActive: vm.selection == .builtin(preset))
                            .listRowBackground(DockColor.surface1)
                            .onTapGesture { vm.select(preset) }
                    }
                }

                Section("Your presets") {
                    if customPresets.isEmpty {
                        Text("No custom presets yet")
                            .font(DockType.font(12))
                            .foregroundStyle(DockColor.textTertiary)
                            .listRowBackground(DockColor.surface1)
                    } else {
                        ForEach(customPresets) { preset in
                            PresetRow(title: preset.name,
                                      subtitle: "Custom · \(bandsRaisedCount(preset.gains)) bands raised",
                                      gains: preset.gains,
                                      isActive: vm.selection == .custom(preset.id))
                                .listRowBackground(DockColor.surface1)
                                .onTapGesture { vm.applyCustom(id: preset.id, gains: preset.gains) }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }
}

#Preview {
    PresetsView(vm: PlaybackViewModel())
        .modelContainer(for: CustomPreset.self, inMemory: true)
}
