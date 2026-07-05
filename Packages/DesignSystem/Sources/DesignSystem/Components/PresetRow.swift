import SwiftUI

/// A preset list row: mini-EQ glyph, title + subtitle, and a teal checkmark when active.
public struct PresetRow: View {
    private let title: String
    private let subtitle: String
    private let gains: [Float]
    private let isActive: Bool

    public init(title: String, subtitle: String, gains: [Float], isActive: Bool) {
        self.title = title
        self.subtitle = subtitle
        self.gains = gains
        self.isActive = isActive
    }

    public var body: some View {
        HStack(spacing: DockSpacing.md) {
            MiniEQIcon(gains: gains)
                .frame(width: 40, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DockType.font(16, .semibold))
                    .foregroundStyle(DockColor.textPrimary)
                Text(subtitle)
                    .font(DockType.font(12))
                    .foregroundStyle(DockColor.textTertiary)
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(DockColor.accent)
            }
        }
        .padding(.vertical, DockSpacing.sm)
        .contentShape(Rectangle())
    }
}

#Preview {
    VStack {
        PresetRow(title: "Brown", subtitle: "Deep, low-end rumble",
                  gains: [10, 7, 4, 1, -2, -5, -8, -11], isActive: true)
        PresetRow(title: "Late night", subtitle: "Custom · 3 bands raised",
                  gains: [4, 3, 2, 0, 0, 0, 0, 0], isActive: false)
    }
    .padding()
    .background(DockColor.background)
}
