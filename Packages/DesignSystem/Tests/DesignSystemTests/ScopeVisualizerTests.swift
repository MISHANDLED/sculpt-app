import Testing
@testable import DesignSystem

@Test func scopeYCentersZero() {
    #expect(scopeY(value: 0, height: 100) == 50)
}

@Test func scopeYMapsExtremes() {
    #expect(scopeY(value: 1, height: 100) == 0)     // +1 -> top
    #expect(scopeY(value: -1, height: 100) == 100)  // -1 -> bottom
}

@Test func scopeYClampsOutOfRange() {
    #expect(scopeY(value: 5, height: 100) == 0)
    #expect(scopeY(value: -5, height: 100) == 100)
}
