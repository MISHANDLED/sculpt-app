import Testing
@testable import DesignSystem

@Test func fillFractionAtMidpoint() {
    #expect(abs(bandSliderFillFraction(value: -6, in: -24...12) - 0.5) < 0.001)
}

@Test func fillFractionClampsAboveAndBelow() {
    #expect(bandSliderFillFraction(value: 100, in: -24...12) == 1)
    #expect(bandSliderFillFraction(value: -100, in: -24...12) == 0)
}
