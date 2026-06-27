import CoreText
import Foundation

public enum FontRegistrar {
    private static var didRegister = false

    /// Registers all bundled Lexend faces with the font manager. Idempotent.
    public static func registerFonts() {
        guard !didRegister else { return }
        didRegister = true
        let names = ["Lexend-Light", "Lexend-Regular", "Lexend-Medium",
                     "Lexend-SemiBold", "Lexend-Bold"]
        for name in names {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf") else {
                assertionFailure("Missing bundled font: \(name).ttf")
                continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
