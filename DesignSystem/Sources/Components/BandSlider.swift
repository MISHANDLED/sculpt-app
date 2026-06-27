import SwiftUI

/// Fraction (0...1) of the track that should be filled for `value` within `range`.
public func bandSliderFillFraction(value: Float, in range: ClosedRange<Float>) -> CGFloat {
    let clamped = min(range.upperBound, max(range.lowerBound, value))
    let span = range.upperBound - range.lowerBound
    guard span > 0 else { return 0 }
    return CGFloat((clamped - range.lowerBound) / span)
}

/// Vertical EQ slider: teal fill from the bottom with a glowing knob.
/// A dumb component — it knows nothing about frequency or audio.
public struct BandSlider: View {
    @Binding private var value: Float
    private let range: ClosedRange<Float>

    public init(value: Binding<Float>, range: ClosedRange<Float>) {
        self._value = value
        self.range = range
    }

    public var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let fraction = bandSliderFillFraction(value: value, in: range)
            let knobY = height * (1 - fraction)

            ZStack(alignment: .bottom) {
                // Track
                Capsule()
                    .fill(DockColor.surface3)
                    .frame(width: 4)
                // Fill
                Capsule()
                    .fill(DockColor.accent)
                    .frame(width: 4, height: height * fraction)
                // Knob
                Circle()
                    .fill(DockColor.accent)
                    .frame(width: 16, height: 16)
                    .shadow(color: DockColor.accent.opacity(0.7), radius: 8)
                    .position(x: geo.size.width / 2, y: knobY)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let f = 1 - min(1, max(0, g.location.y / height))
                        let span = range.upperBound - range.lowerBound
                        value = range.lowerBound + Float(f) * span
                    }
            )
        }
    }
}

#Preview {
    struct Demo: View {
        @State var v: Float = -6
        var body: some View {
            BandSlider(value: $v, range: -24...12)
                .frame(width: 40, height: 200)
                .padding()
                .background(DockColor.background)
        }
    }
    return Demo()
}
