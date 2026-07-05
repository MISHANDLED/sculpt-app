import Testing
@testable import DesignSystem

@Test func fillFractionAtMidpoint() {
    #expect(abs(SliderGeometry.fillFraction(value: -6, in: -24...12) - 0.5) < 0.001)
}

@Test func fillFractionClampsAboveAndBelow() {
    #expect(SliderGeometry.fillFraction(value: 100, in: -24...12) == 1)
    #expect(SliderGeometry.fillFraction(value: -100, in: -24...12) == 0)
}
