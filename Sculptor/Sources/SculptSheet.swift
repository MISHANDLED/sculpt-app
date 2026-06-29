import SwiftUI
import SwiftData
import AudioEngine
import DesignSystem

struct SculptSheet: View {
    @ObservedObject var vm: PlaybackViewModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CustomPreset.sortIndex) private var customPresets: [CustomPreset]


    var body: some View {
        ZStack {
            DockColor.background.ignoresSafeArea()

            VStack(spacing: DockSpacing.xl) {
                header

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
                                .frame(height: 160)
                                Text(freqLabel(vm.frequencies[i]))
                                    .font(DockType.font(10, .medium))
                                    .foregroundStyle(DockColor.textTertiary)
                                    .fixedSize()
                            }
                        }
                    }
                }

                if vm.isEdited {
                    saveButton
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if let err = vm.errorText {
                    Text(err).font(DockType.font(12)).foregroundStyle(.red)
                }
            }
            .padding(DockSpacing.xl)
            .animation(.easeInOut(duration: 0.22), value: vm.isEdited)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Sub-views

    private var header: some View {
        HStack {
            Text("Sculpt")
                .font(DockType.font(24, .semibold))
                .foregroundStyle(DockColor.textPrimary)
            Spacer()
            if vm.isEdited {
                Button(action: { vm.reset() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset")
                            .font(DockType.font(14, .medium))
                    }
                    .foregroundStyle(DockColor.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(DockColor.surface1)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(DockColor.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
    }

    private var saveButton: some View {
        Button {
            savePreset()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                Text("Save as preset")
            }
            .font(DockType.font(16, .medium))
            .foregroundStyle(DockColor.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        DockColor.accent.opacity(0.6),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6])
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func freqLabel(_ f: Float) -> String {
        f >= 1000 ? "\(Int(f / 1000))k" : "\(Int(f))"
    }

    private func savePreset() {
        let nextIndex = (customPresets.map(\.sortIndex).max() ?? -1) + 1
        let preset = CustomPreset(name: "Custom", gains: vm.gains, sortIndex: nextIndex)
        context.insert(preset)
        vm.presetToRename = preset.id
        dismiss()
    }
}

#Preview {
    Color.black
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            SculptSheet(vm: PlaybackViewModel())
                .modelContainer(for: CustomPreset.self, inMemory: true)
        }
}
