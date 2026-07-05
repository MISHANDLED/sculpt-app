import Testing
@testable import AudioEngine

@Test func scopeTapInstallAndRemoveToggleState() {
    let engine = NoiseEngine()
    #expect(engine.isScopeTapInstalled == false)
    engine._installScopeTap()
    #expect(engine.isScopeTapInstalled == true)
    engine._installScopeTap()  // idempotent
    #expect(engine.isScopeTapInstalled == true)
    engine._removeScopeTap()
    #expect(engine.isScopeTapInstalled == false)
}

@Test func disablingScopeRemovesInstalledTap() {
    let engine = NoiseEngine()
    engine._installScopeTap()
    engine.scopeEnabled = false
    #expect(engine.isScopeTapInstalled == false)
}

@Test func enablingScopeWhileStoppedDoesNotInstall() {
    let engine = NoiseEngine()
    engine.scopeEnabled = false
    engine.scopeEnabled = true
    #expect(engine.isScopeTapInstalled == false)   // not playing — nothing to observe
}
