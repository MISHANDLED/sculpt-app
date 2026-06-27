import Testing
@testable import DesignSystem

@Test func decodesAccentTeal() {
    let (r, g, b) = dockRGB(hex: 0x2ED3B7)
    #expect(abs(r - 0x2E / 255.0) < 0.001)
    #expect(abs(g - 0xD3 / 255.0) < 0.001)
    #expect(abs(b - 0xB7 / 255.0) < 0.001)
}

@Test func decodesBlackBackground() {
    let (r, g, b) = dockRGB(hex: 0x0D0D11)
    #expect(abs(r - 0x0D / 255.0) < 0.001)
    #expect(abs(g - 0x0D / 255.0) < 0.001)
    #expect(abs(b - 0x11 / 255.0) < 0.001)
}
