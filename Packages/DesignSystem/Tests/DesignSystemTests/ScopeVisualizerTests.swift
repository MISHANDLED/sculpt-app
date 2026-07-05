import Testing
@testable import DesignSystem

@Test func scopeYCentersZero() {
    #expect(ScopeGeometry.y(value: 0, height: 100) == 50)
}

@Test func scopeYMapsExtremes() {
    #expect(ScopeGeometry.y(value: 1, height: 100) == 0)     // +1 -> top
    #expect(ScopeGeometry.y(value: -1, height: 100) == 100)  // -1 -> bottom
}

@Test func scopeYClampsOutOfRange() {
    #expect(ScopeGeometry.y(value: 5, height: 100) == 0)
    #expect(ScopeGeometry.y(value: -5, height: 100) == 100)
}
