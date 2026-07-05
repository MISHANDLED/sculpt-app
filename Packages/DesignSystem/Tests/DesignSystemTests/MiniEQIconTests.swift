import Testing
@testable import DesignSystem

@Test func barHeightMapsRange() {
    let r: ClosedRange<Float> = -24...12
    #expect(MiniEQGeometry.barHeight(gain: 12, range: r, maxHeight: 20) == 20)   // top -> full
    #expect(MiniEQGeometry.barHeight(gain: -24, range: r, maxHeight: 20) == 0)   // bottom -> empty
}

@Test func barHeightClampsAndIsMonotonic() {
    let r: ClosedRange<Float> = -24...12
    #expect(MiniEQGeometry.barHeight(gain: 100, range: r, maxHeight: 20) == 20)
    #expect(MiniEQGeometry.barHeight(gain: -100, range: r, maxHeight: 20) == 0)
    #expect(MiniEQGeometry.barHeight(gain: 0, range: r, maxHeight: 20)
            > MiniEQGeometry.barHeight(gain: -12, range: r, maxHeight: 20))
}
