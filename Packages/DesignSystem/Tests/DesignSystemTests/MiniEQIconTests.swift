import Testing
@testable import DesignSystem

@Test func barHeightMapsRange() {
    let r: ClosedRange<Float> = -24...12
    #expect(miniEQBarHeight(gain: 12, range: r, maxHeight: 20) == 20)   // top -> full
    #expect(miniEQBarHeight(gain: -24, range: r, maxHeight: 20) == 0)   // bottom -> empty
}

@Test func barHeightClampsAndIsMonotonic() {
    let r: ClosedRange<Float> = -24...12
    #expect(miniEQBarHeight(gain: 100, range: r, maxHeight: 20) == 20)
    #expect(miniEQBarHeight(gain: -100, range: r, maxHeight: 20) == 0)
    #expect(miniEQBarHeight(gain: 0, range: r, maxHeight: 20)
            > miniEQBarHeight(gain: -12, range: r, maxHeight: 20))
}
