import Testing
@testable import Sculptor
import AudioEngine
import Foundation

@MainActor
@Suite struct PlaybackViewModelTests {
    @Test func selectPresetSetsBuiltinSelection() {
        let vm = PlaybackViewModel()
        vm.select(.pink)
        #expect(vm.gains == NoisePreset.pink.gains)
        #expect(vm.selection == .builtin(.pink))
    }

    @Test func applyCustomSetsCustomSelectionAndGains() {
        let vm = PlaybackViewModel()
        let id = UUID()
        let g: [Float] = [3, 2, 1, 0, -1, -2, -3, -4]
        vm.applyCustom(id: id, gains: g)
        #expect(vm.gains == g)
        #expect(vm.selection == .custom(id))
    }

    @Test func draggingABandClearsSelection() {
        let vm = PlaybackViewModel()
        vm.select(.pink)
        vm.setGain(band: 0, dB: 5)
        #expect(vm.selection == .none)
        #expect(vm.gains[0] == 5)
    }

    @Test func ingestScopeSamplesIgnoredWhenPaused() {
        let vm = PlaybackViewModel()
        vm._ingestScopeSamples([1, 2, 3])
        #expect(vm.scopeSamples == [])
    }
}
