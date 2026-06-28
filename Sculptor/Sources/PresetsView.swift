import SwiftUI
import SwiftData
import AudioEngine
import DesignSystem

struct PresetsView: View {
    @ObservedObject var vm: PlaybackViewModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CustomPreset.sortIndex) private var customPresets: [CustomPreset]

    @State private var showingSave = false
    @State private var newName = ""
    @State private var editMode = EditMode.inactive

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
            VStack(spacing: 0) {
                navHeader
                List {
                    Section {
                        ForEach(builtins, id: \.0) { preset, title, subtitle in
                            PresetRow(
                                title: title, subtitle: subtitle, gains: preset.gains,
                                isActive: !vm.isEdited && vm.selection == .builtin(preset)
                            )
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
                                PresetRow(
                                    title: preset.name,
                                    subtitle: "Custom · \(bandsRaisedCount(preset.gains)) bands raised",
                                    gains: preset.gains,
                                    isActive: !vm.isEdited && vm.selection == .custom(preset.id)
                                )
                                .listRowBackground(DockColor.surface1)
                                .onTapGesture { vm.applyCustom(id: preset.id, gains: preset.gains) }
                            }
                            .onMove { indices, newOffset in
                                var items = customPresets
                                items.move(fromOffsets: indices, toOffset: newOffset)
                                for (i, p) in items.enumerated() { p.sortIndex = i }
                            }
                            .onDelete { offsets in
                                for i in offsets { context.delete(customPresets[i]) }
                            }
                        }
                    }

                    Section {
                        Button {
                            newName = ""
                            showingSave = true
                        } label: {
                            Label("Save current as preset", systemImage: "plus")
                                .font(DockType.font(16, .medium))
                                .foregroundStyle(DockColor.accent)
                        }
                        .listRowBackground(DockColor.surface1)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .alert("Save preset", isPresented: $showingSave) {
                    TextField("Name", text: $newName)
                    Button("Save") { savePreset() }
                    Button("Cancel", role: .cancel) {}
                }
                .environment(\.editMode, $editMode)
            }
        }
    }

    private var navHeader: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DockColor.textPrimary)
            }
            .buttonStyle(.plain)
            Spacer()
            Text("Presets")
                .font(DockType.font(18, .semibold))
                .foregroundStyle(DockColor.textPrimary)
            Spacer()
            Button(editMode == .inactive ? "Edit" : "Done") {
                editMode = editMode == .inactive ? .active : .inactive
            }
            .font(DockType.font(14, .medium))
            .foregroundStyle(DockColor.accent)
        }
        .padding(DockSpacing.xl)
    }

    private func savePreset() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "Custom" : trimmed
        let nextIndex = (customPresets.map(\.sortIndex).max() ?? -1) + 1
        context.insert(CustomPreset(name: name, gains: vm.gains, sortIndex: nextIndex))
    }
}

#Preview {
    PresetsView(vm: PlaybackViewModel())
        .modelContainer(for: CustomPreset.self, inMemory: true)
}
