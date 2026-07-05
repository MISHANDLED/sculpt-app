import SwiftUI

public enum DockType {
    public enum Weight {
        case light, regular, medium, semibold, bold
    }

    /// Pure map from a semantic weight to the bundled font's PostScript name.
    /// The Dock design system ships Lexend with `Dock-`-prefixed PostScript names
    /// (the `.ttf` filenames are `Lexend-*`, but the internal names are these).
    public static func lexendFontName(for weight: Weight) -> String {
        switch weight {
        case .light:    return "Dock-Lexend-Light"
        case .regular:  return "Dock-Lexend-Regular"
        case .medium:   return "Dock-Lexend-Medium"
        case .semibold: return "Dock-Lexend-SemiBold"
        case .bold:     return "Dock-Lexend-Bold"
        }
    }

    /// A Lexend `Font` at the given point size and weight. Ensures fonts are registered.
    public static func font(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        FontRegistrar.registerFonts()
        return .custom(lexendFontName(for: weight), fixedSize: size)
    }
}
