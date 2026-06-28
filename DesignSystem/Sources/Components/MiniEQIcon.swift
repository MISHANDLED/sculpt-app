import SwiftUI

/// Height of one mini-EQ bar for `gain` within `range`, clamped to 0...maxHeight.
public func miniEQBarHeight(gain: Float, range: ClosedRange<Float>, maxHeight: CGFloat) -> CGFloat {
    let clamped = min(range.upperBound, max(range.lowerBound, gain))
    let span = range.upperBound - range.lowerBound
    guard span > 0 else { return 0 }
    return maxHeight * CGFloat((clamped - range.lowerBound) / span)
}

/// Compact glyph rendering a gain set as tiny teal bars (the preset-row icon).
public struct MiniEQIcon: View {
    private let gains: [Float]
    private let range: ClosedRange<Float>

    public init(gains: [Float], range: ClosedRange<Float> = -24...12) {
        self.gains = gains
        self.range = range
    }

    public var body: some View {
        GeometryReader { geo in
            let maxH = geo.size.height
            let count = max(gains.count, 1)
            let barW = geo.size.width / CGFloat(count) * 0.6
            HStack(alignment: .bottom, spacing: geo.size.width / CGFloat(count) * 0.4) {
                ForEach(0..<gains.count, id: \.self) { i in
                    Capsule()
                        .fill(DockColor.accent)
                        .frame(width: barW,
                               height: max(1, miniEQBarHeight(gain: gains[i], range: range, maxHeight: maxH)))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

#Preview {
    MiniEQIcon(gains: [10, 6, 2, -2, -6, -2, 4, 8])
        .frame(width: 40, height: 28)
        .padding()
        .background(DockColor.background)
}
