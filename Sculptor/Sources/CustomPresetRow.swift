import SwiftUI
import DesignSystem

/// A custom-preset list row: mini-EQ glyph, title/subtitle (or an inline rename
/// TextField), an active checkmark, and a trailing 3-dot menu (Rename/Copy/Delete).
struct CustomPresetRow: View {
    let name: String
    let subtitle: String
    let gains: [Float]
    let isActive: Bool
    let isRenaming: Bool
    @Binding var renameText: String
    var renameFocus: FocusState<Bool>.Binding
    let onBeginRename: () -> Void
    let onCommitRename: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: DockSpacing.md) {
            MiniEQIcon(gains: gains)
                .frame(width: 40, height: 28)

            if isRenaming {
                TextField("Name", text: $renameText)
                    .font(DockType.font(16, .semibold))
                    .foregroundStyle(DockColor.textPrimary)
                    .focused(renameFocus)
                    .submitLabel(.done)
                    .onSubmit { onCommitRename() }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(DockType.font(16, .semibold))
                        .foregroundStyle(DockColor.textPrimary)
                    Text(subtitle)
                        .font(DockType.font(12))
                        .foregroundStyle(DockColor.textTertiary)
                }
            }

            Spacer()

            if isActive && !isRenaming {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(DockColor.accent)
            }

            if !isRenaming {
                Menu {
                    Button { onBeginRename() } label: { Label("Rename", systemImage: "pencil") }
                    Button { onCopy() } label: { Label("Copy", systemImage: "doc.on.doc") }
                    Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DockColor.textTertiary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, DockSpacing.sm)
        .contentShape(Rectangle())
        .task(id: isRenaming) {
            if isRenaming { renameFocus.wrappedValue = true }
        }
    }
}
