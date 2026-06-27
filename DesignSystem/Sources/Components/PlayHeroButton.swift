import SwiftUI

/// Large circular play/pause hero button: teal fill, glowing ring.
public struct PlayHeroButton: View {
    private let isPlaying: Bool
    private let action: () -> Void

    public init(isPlaying: Bool, action: @escaping () -> Void) {
        self.isPlaying = isPlaying
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(DockColor.accent)
                    .frame(width: 140, height: 140)
                    .shadow(color: DockColor.accent.opacity(0.6), radius: 24)
                Circle()
                    .stroke(DockColor.accent.opacity(0.5), lineWidth: 2)
                    .frame(width: 160, height: 160)
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(DockColor.background)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
    }
}

#Preview {
    VStack(spacing: 40) {
        PlayHeroButton(isPlaying: false) {}
        PlayHeroButton(isPlaying: true) {}
    }
    .padding()
    .background(DockColor.background)
}
