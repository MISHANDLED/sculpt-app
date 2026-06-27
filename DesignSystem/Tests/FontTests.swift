import Testing
import UIKit
@testable import DesignSystem

@Test func weightMapsToPostScriptName() {
    #expect(DockType.lexendFontName(for: .regular) == "Lexend-Regular")
    #expect(DockType.lexendFontName(for: .bold) == "Lexend-Bold")
    #expect(DockType.lexendFontName(for: .semibold) == "Lexend-SemiBold")
}

@Test func registeredFontIsResolvable() {
    FontRegistrar.registerFonts()
    #expect(UIFont(name: "Lexend-Regular", size: 12) != nil)
    #expect(UIFont(name: "Lexend-Bold", size: 12) != nil)
}
