import SwiftUI

/// Maps a sample (roughly -1...1, clamped) to a Y coordinate: 0 -> vertical
/// center, +1 -> top (0), -1 -> bottom (height).
public func scopeY(value: Float, height: CGFloat) -> CGFloat {
    let clamped = CGFloat(min(1, max(-1, value)))
    return height / 2 - clamped * (height / 2)
}

/// Oscilloscope-style visualizer: a glowing teal polyline drawn through the
/// sample window across the full width. Empty samples render a flat center line.
public struct ScopeVisualizer: View {
    private let samples: [Float]

    public init(samples: [Float]) {
        self.samples = samples
    }

    public var body: some View {
        Canvas { context, size in
            var path = Path()
            let n = samples.count
            if n < 2 {
                let mid = size.height / 2
                path.move(to: CGPoint(x: 0, y: mid))
                path.addLine(to: CGPoint(x: size.width, y: mid))
            } else {
                for i in 0..<n {
                    let x = size.width * CGFloat(i) / CGFloat(n - 1)
                    let y = scopeY(value: samples[i], height: size.height)
                    let pt = CGPoint(x: x, y: y)
                    if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
            }
            // Glow underlay + crisp line.
            context.stroke(path, with: .color(DockColor.accent.opacity(0.4)),
                           style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            context.stroke(path, with: .color(DockColor.accent),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}

#Preview {
    ScopeVisualizer(samples: (0..<128).map { sinf(Float($0) / 8) })
        .frame(height: 80)
        .padding()
        .background(DockColor.background)
}
