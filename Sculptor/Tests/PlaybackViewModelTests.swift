import Testing
@testable import Sculptor
import AudioEngine

@MainActor
@Test func selectPresetUpdatesGainsAndSelection() {
    let vm = PlaybackViewModel()
    vm.select(.pink)
    #expect(vm.gains == NoisePreset.pink.gains)
    #expect(vm.selectedPreset == .pink)
}

@MainActor
@Test func draggingABandClearsSelectedPreset() {
    let vm = PlaybackViewModel()
    vm.select(.pink)
    vm.setGain(band: 0, dB: 5)
    #expect(vm.selectedPreset == nil)
    #expect(vm.gains[0] == 5)
}

@MainActor
@Test func ingestScopeSamplesUpdatesPublishedWindow() {
    let vm = PlaybackViewModel()
    vm._ingestScopeSamples([0.1, -0.2, 0.3])
    #expect(vm.scopeSamples == [0.1, -0.2, 0.3])
}
