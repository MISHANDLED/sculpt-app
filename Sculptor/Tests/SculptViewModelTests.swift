import Testing
@testable import Sculptor
import AudioEngine

@MainActor
@Test func selectPresetUpdatesGainsAndSelection() {
    let vm = SculptViewModel()
    vm.select(.pink)
    #expect(vm.gains == NoisePreset.pink.gains)
    #expect(vm.selectedPreset == .pink)
}

@MainActor
@Test func draggingABandClearsSelectedPreset() {
    let vm = SculptViewModel()
    vm.select(.pink)
    vm.setGain(band: 0, dB: 5)
    #expect(vm.selectedPreset == nil)
    #expect(vm.gains[0] == 5)
}
