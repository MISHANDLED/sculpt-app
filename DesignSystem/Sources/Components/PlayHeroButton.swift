import SwiftUI

public struct PlayHeroButton: View {
    private let isPlaying: Bool
    private let action: () -> Void
    @State private var pulsing = false

    public init(isPlaying: Bool, action: @escaping () -> Void) {
        self.isPlaying = isPlaying
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(DockColor.accent.opacity(0.35), lineWidth: 1.5)
                        .frame(width: 138 + CGFloat(i + 1) * 24,
                               height: 138 + CGFloat(i + 1) * 24)
                        .scaleEffect(pulsing ? 1.1 : 1.0)
                        .opacity(pulsing ? 0.0 : 0.5)
                        .animation(
                            pulsing
                                ? .easeOut(duration: 1.3)
                                    .repeatForever(autoreverses: false)
                                    .delay(Double(i) * 0.42)
                                : .none,
                            value: pulsing
                        )
                }
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [DockColor.accent, accentDark],
                            center: .center,
                            startRadius: 0,
                            endRadius: 69
                        )
                    )
                    .frame(width: 138, height: 138)
                    .shadow(color: DockColor.accent.opacity(0.6), radius: 24)
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(DockColor.background)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
        .onChange(of: isPlaying, initial: true) { _, playing in
            pulsing = playing
        }
    }

    private var accentDark: Color {
        // #0e7d6c — darker teal for the radial gradient inner-to-outer effect
        let (r, g, b) = dockRGB(hex: 0x0e7d6c)
        return Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

#Preview {
    VStack(spacing: 48) {
        PlayHeroButton(isPlaying: false) {}
        PlayHeroButton(isPlaying: true) {}
    }
    .padding(60)
    .background(DockColor.background)
}
