import SwiftUI

/// Selectable pill. Selected = teal fill; unselected = subtle surface + border.
public struct PresetChip: View {
    private let title: String
    private let isSelected: Bool
    private let action: () -> Void

    public init(title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(DockType.font(14, .medium))
                .foregroundStyle(isSelected ? DockColor.background : DockColor.textSecondary)
                .padding(.horizontal, DockSpacing.lg)
                .padding(.vertical, DockSpacing.sm)
                .background(
                    Capsule().fill(isSelected ? DockColor.accent : DockColor.surface2)
                )
                .overlay(
                    Capsule().stroke(isSelected ? DockColor.accent : DockColor.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    HStack {
        PresetChip(title: "White", isSelected: true) {}
        PresetChip(title: "Pink", isSelected: false) {}
    }
    .padding()
    .background(DockColor.background)
}
