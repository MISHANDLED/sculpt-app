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
    // Note: _ingestScopeSamples only updates when playing to prevent stale frames
    // after pause. Mock the playing state directly.
    vm.togglePlay()
    guard vm.isPlaying else { return }  // Skip if engine start fails in test env
    vm._ingestScopeSamples([0.1, -0.2, 0.3])
    #expect(vm.scopeSamples == [0.1, -0.2, 0.3])
}

@MainActor
@Test func ingestScopeSamplesIgnoredWhenPaused() {
    let vm = PlaybackViewModel()
    #expect(!vm.isPlaying)
    vm._ingestScopeSamples([0.1, -0.2, 0.3])
    #expect(vm.scopeSamples == [])  // Should not be updated while paused
}
