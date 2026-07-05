import SwiftUI

/// Circular DJ-style volume control: dark 270° track with a glowing accent
/// arc and tip dot. Shows an SF Symbol at rest and the bare 0–100 value
/// while the finger is down. Circular drag only.
public struct VolumeKnob: View {
    @Binding var value: Float
    let icon: String
    let label: String

    @State private var isDragging = false
    @State private var lastValue: Float = -1

    private let size: CGFloat = 110
    private let trackWidth: CGFloat = 8

    public init(value: Binding<Float>, icon: String, label: String) {
        _value = value
        self.icon = icon
        self.label = label
    }

    public var body: some View {
        VStack(spacing: DockSpacing.sm) {
            ZStack {
                arc(to: 0.75, color: DockColor.surface3)
                arc(to: KnobGeometry.trimFraction(forValue: value), color: DockColor.accent)
                    .shadow(color: DockColor.accent.opacity(0.55), radius: 6)
                tipDot
                centerReadout
            }
            .frame(width: size, height: size)
            .contentShape(Circle().inset(by: -trackWidth))
            .gesture(dragGesture)
            Text(label)
                .font(DockType.font(11))
                .kerning(2.5)
                .foregroundStyle(DockColor.textTertiary)
        }
    }

    private func arc(to trim: CGFloat, color: Color) -> some View {
        Circle()
            .trim(from: 0, to: trim)
            .stroke(color, style: StrokeStyle(lineWidth: trackWidth, lineCap: .round))
            // trim 0 sits at 3 o'clock; +135° puts it at the sweep start (7:30).
            .rotationEffect(.degrees(135))
    }

    private var tipDot: some View {
        let angle = Double(KnobGeometry.angle(forValue: value))
        return Circle()
            .fill(Color.white)
            .frame(width: 10, height: 10)
            .shadow(color: DockColor.accent, radius: 4)
            .offset(y: -size / 2)
            .rotationEffect(.degrees(angle))
    }

    @ViewBuilder private var centerReadout: some View {
        if isDragging {
            Text("\(Int((value * 100).rounded()))")
                .font(DockType.font(30))
                .fontWeight(.semibold)
                .foregroundStyle(DockColor.textPrimary)
        } else {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(DockColor.accent)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                isDragging = true
                let center = CGPoint(x: size / 2, y: size / 2)
                let angle = KnobGeometry.touchAngle(location: g.location, center: center)
                let newValue = KnobGeometry.value(forAngle: angle)
                if (newValue == 0 || newValue == 1), lastValue != newValue {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                lastValue = newValue
                value = newValue
            }
            .onEnded { _ in
                isDragging = false
                lastValue = -1
            }
    }
}
