import SwiftUI

/// Decodes a 0xRRGGBB integer into sRGB components in 0...1.
func dockRGB(hex: UInt32) -> (Double, Double, Double) {
    let r = Double((hex >> 16) & 0xFF) / 255.0
    let g = Double((hex >> 8) & 0xFF) / 255.0
    let b = Double(hex & 0xFF) / 255.0
    return (r, g, b)
}

private extension Color {
    init(dockHex hex: UInt32) {
        let (r, g, b) = dockRGB(hex: hex)
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

/// Semantic Dock dark-theme colors. Source: colors_and_type.css (dark theme).
public enum DockColor {
    public static let accent        = Color(dockHex: 0x2ED3B7) // teal-400
    public static let background    = Color(dockHex: 0x0D0D11) // black-dark
    public static let surface1      = Color(dockHex: 0x17171C) // grey-dark-900
    public static let surface2      = Color(dockHex: 0x202027) // grey-dark-800
    public static let surface3      = Color(dockHex: 0x2F2F37) // grey-dark-700
    public static let textPrimary   = Color(dockHex: 0xFAFAFA) // grey-dark-50
    public static let textSecondary = Color(dockHex: 0xCACACE) // grey-dark-300
    public static let textTertiary  = Color(dockHex: 0x95959D) // grey-dark-400
    public static let border        = Color(dockHex: 0x2F2F37) // grey-dark-700
}
