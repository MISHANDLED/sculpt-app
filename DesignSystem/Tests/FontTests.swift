import Testing
import UIKit
@testable import DesignSystem

@Test func weightMapsToPostScriptName() {
    #expect(DockType.lexendFontName(for: .regular) == "Dock-Lexend-Regular")
    #expect(DockType.lexendFontName(for: .bold) == "Dock-Lexend-Bold")
    #expect(DockType.lexendFontName(for: .semibold) == "Dock-Lexend-SemiBold")
}

@Test func registeredFontIsResolvable() {
    FontRegistrar.registerFonts()
    #expect(UIFont(name: "Dock-Lexend-Regular", size: 12) != nil)
    #expect(UIFont(name: "Dock-Lexend-Bold", size: 12) != nil)
}
