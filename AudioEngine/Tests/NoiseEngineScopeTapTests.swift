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
