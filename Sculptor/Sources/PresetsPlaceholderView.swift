import SwiftUI
import DesignSystem

struct PresetsPlaceholderView: View {
    var body: some View {
        ZStack {
            DockColor.background.ignoresSafeArea()
            VStack(spacing: DockSpacing.sm) {
                Text("Your presets")
                    .font(DockType.font(20, .semibold))
                    .foregroundStyle(DockColor.textPrimary)
                Text("Coming soon")
                    .font(DockType.font(14))
                    .foregroundStyle(DockColor.textTertiary)
            }
        }
    }
}

#Preview { PresetsPlaceholderView() }
