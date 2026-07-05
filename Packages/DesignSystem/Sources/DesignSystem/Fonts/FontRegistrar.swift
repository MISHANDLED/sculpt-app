import CoreText
import Foundation

public enum FontRegistrar {
    private static var didRegister = false

    /// Registers all bundled Lexend faces with the font manager. Idempotent.
    /// The `.ttf` filenames are `Lexend-*`; the fonts' internal PostScript names
    /// are `Dock-Lexend-*` (see DockType.lexendFontName) — different strings.
    public static func registerFonts() {
        guard !didRegister else { return }
        didRegister = true
        let fileNames = ["Lexend-Light", "Lexend-Regular", "Lexend-Medium",
                         "Lexend-SemiBold", "Lexend-Bold"]
        for fileName in fileNames {
            guard let url = Bundle.module.url(forResource: fileName, withExtension: "ttf") else {
                assertionFailure("Missing bundled font: \(fileName).ttf")
                continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
