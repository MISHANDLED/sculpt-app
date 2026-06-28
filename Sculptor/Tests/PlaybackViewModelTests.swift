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

    // UPDATED: setGain now sets isEdited=true and PRESERVES selection
    @Test func draggingABandSetsIsEditedAndPreservesSelection() {
        let vm = PlaybackViewModel()
        vm.select(.pink)
        vm.setGain(band: 0, dB: 5)
        #expect(vm.selection == .builtin(.pink))   // preserved
        #expect(vm.isEdited == true)
        #expect(vm.gains[0] == 5)
    }

    @Test func selectClearsIsEdited() {
        let vm = PlaybackViewModel()
        vm.setGain(band: 0, dB: 5)
        vm.select(.pink)
        #expect(vm.isEdited == false)
        #expect(vm.selection == .builtin(.pink))
    }

    @Test func applyCustomClearsIsEdited() {
        let vm = PlaybackViewModel()
        vm.setGain(band: 0, dB: 5)
        let id = UUID()
        vm.applyCustom(id: id, gains: [Float](repeating: 0, count: 8))
        #expect(vm.isEdited == false)
        #expect(vm.selection == .custom(id))
    }

    @Test func resetZerosGainsAndClearsState() {
        let vm = PlaybackViewModel()
        vm.select(.pink)
        vm.setGain(band: 0, dB: 5)
        vm.reset()
        #expect(vm.gains.allSatisfy { $0 == 0 })
        #expect(vm.selection == .none)
        #expect(vm.isEdited == false)
    }

    @Test func builtinDisplayName() {
        let vm = PlaybackViewModel()
        vm.select(.pink)
        #expect(vm.presetDisplayName == "Pink")
        vm.select(.white)
        #expect(vm.presetDisplayName == "White")
        vm.select(.brown)
        #expect(vm.presetDisplayName == "Brown")
        vm.select(.grey)
        #expect(vm.presetDisplayName == "Grey")
        vm.select(.speechBlocker)
        #expect(vm.presetDisplayName == "Speech blocker")
    }

    @Test func noneDisplayName() {
        let vm = PlaybackViewModel()
        #expect(vm.presetDisplayName == "Custom")
    }

    @Test func presetToRenameSetAndClear() {
        let vm = PlaybackViewModel()
        #expect(vm.presetToRename == nil)
        let id = UUID()
        vm.presetToRename = id
        #expect(vm.presetToRename == id)
        vm.presetToRename = nil
        #expect(vm.presetToRename == nil)
    }

    @Test func ingestScopeSamplesIgnoredWhenPaused() {
        let vm = PlaybackViewModel()
        vm._ingestScopeSamples([1, 2, 3])
        #expect(vm.scopeSamples == [])
    }
}
