import SwiftUI
import SwiftData
import AudioEngine
import DesignSystem

struct PresetsView: View {
    @ObservedObject var vm: PlaybackViewModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CustomPreset.sortIndex) private var customPresets: [CustomPreset]

    @State private var editMode = EditMode.inactive
    @State private var renamingID: UUID?
    @State private var renameText = ""
    @FocusState private var renameFieldFocused: Bool

    private let builtins: [(NoisePreset, String, String)] = [
        (.brown, "Brown", "Deep, low-end rumble"),
        (.pink, "Pink", "Balanced, natural tilt"),
        (.white, "White", "Flat across the spectrum"),
        (.grey, "Grey", "Equal-loudness shaped"),
        (.speechBlocker, "Speech blocker", "Masks nearby conversation")
    ]

    // System NavigationStack toolbar so iPhone Duo can lay the bar out
    // vertically (closed display, inner landscape).
    var body: some View {
        NavigationStack {
            ZStack {
                DockColor.background.ignoresSafeArea()
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
                                CustomPresetRow(
                                    name: preset.name,
                                    subtitle: "Custom · \(PresetMetrics.bandsRaisedCount(preset.gains)) bands raised",
                                    gains: preset.gains,
                                    isActive: !vm.isEdited && vm.selection == .custom(preset.id),
                                    isRenaming: renamingID == preset.id,
                                    renameText: $renameText,
                                    renameFocus: $renameFieldFocused,
                                    onBeginRename: { beginRename(preset) },
                                    onCommitRename: { commitRename(preset) },
                                    onCopy: { copyPreset(preset) },
                                    onDelete: { context.delete(preset) }
                                )
                                .listRowBackground(DockColor.surface1)
                                .onTapGesture {
                                    guard renamingID == nil else { return }
                                    vm.applyCustom(id: preset.id, gains: preset.gains)
                                }
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
                            saveCurrentAsPreset()
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
                .environment(\.editMode, $editMode)
            }
            .navigationTitle("Presets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Icon + title on every item: vertical bars show icons only.
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back", systemImage: "chevron.left") { dismiss() }
                        .tint(DockColor.textPrimary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(
                        editMode == .inactive ? "Edit" : "Done",
                        systemImage: editMode == .inactive ? "pencil" : "checkmark"
                    ) {
                        editMode = editMode == .inactive ? .active : .inactive
                    }
                    .tint(DockColor.accent)
                }
            }
        }
        .onAppear { consumePendingRename() }
        .onChange(of: vm.presetToRename) { _, _ in consumePendingRename() }
        .onChange(of: customPresets.count) { _, _ in consumePendingRename() }
    }

    // MARK: - Actions

    private func beginRename(_ preset: CustomPreset) {
        renameText = preset.name
        renamingID = preset.id
    }

    private func commitRename(_ preset: CustomPreset) {
        preset.name = PresetMetrics.sanitizedRename(old: preset.name, new: renameText)
        renamingID = nil
    }

    private func copyPreset(_ preset: CustomPreset) {
        let nextIndex = (customPresets.map(\.sortIndex).max() ?? -1) + 1
        context.insert(CustomPreset(name: PresetMetrics.copyName(of: preset.name), gains: preset.gains, sortIndex: nextIndex))
    }

    private func saveCurrentAsPreset() {
        let nextIndex = (customPresets.map(\.sortIndex).max() ?? -1) + 1
        let preset = CustomPreset(name: "Custom", gains: vm.gains, sortIndex: nextIndex)
        context.insert(preset)
        vm.presetToRename = preset.id
    }

    private func consumePendingRename() {
        guard let id = vm.presetToRename else { return }
        guard let preset = customPresets.first(where: { $0.id == id }) else { return }
        renameText = preset.name
        renamingID = id
        vm.presetToRename = nil
    }
}

#Preview {
    PresetsView(vm: PlaybackViewModel())
        .modelContainer(for: CustomPreset.self, inMemory: true)
}
