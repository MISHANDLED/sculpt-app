import SwiftUI

public enum DockType {
    public enum Weight {
        case light, regular, medium, semibold, bold
    }

    /// Pure map from a semantic weight to the bundled font's PostScript name.
    public static func lexendFontName(for weight: Weight) -> String {
        switch weight {
        case .light:    return "Lexend-Light"
        case .regular:  return "Lexend-Regular"
        case .medium:   return "Lexend-Medium"
        case .semibold: return "Lexend-SemiBold"
        case .bold:     return "Lexend-Bold"
        }
    }

    /// A Lexend `Font` at the given point size and weight. Ensures fonts are registered.
    public static func font(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        FontRegistrar.registerFonts()
        return .custom(lexendFontName(for: weight), fixedSize: size)
    }
}
