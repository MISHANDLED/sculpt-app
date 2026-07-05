import SwiftUI

/// Rounded surface container used to group controls.
public struct DockCard<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(DockSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: DockRadius.card)
                    .fill(DockColor.surface1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DockRadius.card)
                    .stroke(DockColor.border, lineWidth: 1)
            )
    }
}

#Preview {
    DockCard { Text("Card").foregroundStyle(DockColor.textPrimary) }
        .padding()
        .background(DockColor.background)
}
