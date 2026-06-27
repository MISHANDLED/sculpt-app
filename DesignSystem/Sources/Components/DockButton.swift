import SwiftUI

/// Primary (teal) or secondary (surface) action button.
public struct DockButton: View {
    public enum Style { case primary, secondary }

    private let title: String
    private let style: Style
    private let action: () -> Void

    public init(title: String, style: Style = .primary, action: @escaping () -> Void) {
        self.title = title
        self.style = style
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(DockType.font(18, .semibold))
                .foregroundStyle(style == .primary ? DockColor.background : DockColor.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DockSpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: DockRadius.chip)
                        .fill(style == .primary ? DockColor.accent : DockColor.surface2)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack {
        DockButton(title: "Play") {}
        DockButton(title: "Pause", style: .secondary) {}
    }
    .padding()
    .background(DockColor.background)
}
