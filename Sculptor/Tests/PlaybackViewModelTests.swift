import Testing
@testable import Sculptor
import AudioEngine
import Foundation

@MainActor
@Suite struct PlaybackViewModelTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "test-\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    @Test func selectPresetSetsBuiltinSelection() {
        let vm = PlaybackViewModel(defaults: freshDefaults())
        vm.select(.pink)
        #expect(vm.gains == NoisePreset.pink.gains)
        #expect(vm.selection == .builtin(.pink))
    }

    @Test func applyCustomSetsCustomSelectionAndGains() {
        let vm = PlaybackViewModel(defaults: freshDefaults())
        let id = UUID()
        let g: [Float] = [3, 2, 1, 0, -1, -2, -3, -4]
        vm.applyCustom(id: id, gains: g)
        #expect(vm.gains == g)
        #expect(vm.selection == .custom(id))
    }

    // UPDATED: setGain now sets isEdited=true and PRESERVES selection
    @Test func draggingABandSetsIsEditedAndPreservesSelection() {
        let vm = PlaybackViewModel(defaults: freshDefaults())
        vm.select(.pink)
        vm.setGain(band: 0, dB: 5)
        #expect(vm.selection == .builtin(.pink))   // preserved
        #expect(vm.isEdited == true)
        #expect(vm.gains[0] == 5)
    }

    @Test func selectClearsIsEdited() {
        let vm = PlaybackViewModel(defaults: freshDefaults())
        vm.setGain(band: 0, dB: 5)
        vm.select(.pink)
        #expect(vm.isEdited == false)
        #expect(vm.selection == .builtin(.pink))
    }

    @Test func applyCustomClearsIsEdited() {
        let vm = PlaybackViewModel(defaults: freshDefaults())
        vm.setGain(band: 0, dB: 5)
        let id = UUID()
        vm.applyCustom(id: id, gains: [Float](repeating: 0, count: 8))
        #expect(vm.isEdited == false)
        #expect(vm.selection == .custom(id))
    }

    @Test func resetZerosGainsAndClearsState() {
        let vm = PlaybackViewModel(defaults: freshDefaults())
        vm.select(.pink)
        vm.setGain(band: 0, dB: 5)
        vm.reset()
        #expect(vm.gains.allSatisfy { $0 == 0 })
        #expect(vm.selection == .none)
        #expect(vm.isEdited == false)
    }

    @Test func builtinDisplayName() {
        let vm = PlaybackViewModel(defaults: freshDefaults())
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
        let vm = PlaybackViewModel(defaults: freshDefaults())
        #expect(vm.presetDisplayName == "Custom")
    }

    @Test func presetToRenameSetAndClear() {
        let vm = PlaybackViewModel(defaults: freshDefaults())
        #expect(vm.presetToRename == nil)
        let id = UUID()
        vm.presetToRename = id
        #expect(vm.presetToRename == id)
        vm.presetToRename = nil
        #expect(vm.presetToRename == nil)
    }

    @Test func ingestScopeSamplesIgnoredWhenPaused() {
        let vm = PlaybackViewModel(defaults: freshDefaults())
        vm._ingestScopeSamples([1, 2, 3])
        #expect(vm.scopeSamples == [])
    }

    @Test func startSleepTimerSetsMinutesAndRemaining() {
        let vm = PlaybackViewModel(defaults: freshDefaults())
        vm.startSleepTimer(minutes: 30)
        #expect(vm.sleepMinutes == 30)
        let remaining = vm.sleepRemaining ?? 0
        #expect(remaining > 30 * 60 - 1 && remaining <= 30 * 60)
        vm.cancelSleepTimer()   // stop the tick loop
    }

    @Test func cancelSleepTimerClearsState() {
        let vm = PlaybackViewModel(defaults: freshDefaults())
        vm.startSleepTimer(minutes: 15)
        vm.cancelSleepTimer()
        #expect(vm.sleepMinutes == nil)
        #expect(vm.sleepRemaining == nil)
    }

    @Test func sleepTickBeforeDeadlineUpdatesRemaining() {
        let vm = PlaybackViewModel(defaults: freshDefaults())
        vm.startSleepTimer(minutes: 30)
        vm._sleepTick(now: Date().addingTimeInterval(60))  // 1 minute elapsed
        let remaining = vm.sleepRemaining ?? 0
        #expect(remaining > 28 * 60 && remaining < 30 * 60)
        #expect(vm.sleepMinutes == 30)
        vm.cancelSleepTimer()
    }

    @Test func sleepTickPastDeadlineStopsAndClears() {
        let vm = PlaybackViewModel(defaults: freshDefaults())
        vm.startSleepTimer(minutes: 30)
        vm._sleepTick(now: Date().addingTimeInterval(31 * 60))  // past deadline
        #expect(vm.sleepRemaining == nil)
        #expect(vm.sleepMinutes == nil)
        #expect(vm.isPlaying == false)
    }

    @Test func startSleepTimerTwiceReplacesDuration() {
        let vm = PlaybackViewModel(defaults: freshDefaults())
        vm.startSleepTimer(minutes: 15)
        vm.startSleepTimer(minutes: 45)
        #expect(vm.sleepMinutes == 45)
        vm.cancelSleepTimer()
    }

    // MARK: - Restore tests (shared suite simulates relaunch)

    @Test func restoresLastBuiltinSelection() {
        let suite = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let vm1 = PlaybackViewModel(defaults: suite)
        vm1.select(.pink)
        let vm2 = PlaybackViewModel(defaults: suite)
        #expect(vm2.selection == .builtin(.pink))
        #expect(vm2.gains == NoisePreset.pink.gains)
    }

    @Test func restoresLastCustomSelection() {
        let suite = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let vm1 = PlaybackViewModel(defaults: suite)
        let id = UUID()
        let g: [Float] = [3, 2, 1, 0, -1, -2, -3, -4]
        vm1.applyCustom(id: id, gains: g)
        let vm2 = PlaybackViewModel(defaults: suite)
        #expect(vm2.selection == .custom(id))
        #expect(vm2.gains == g)
    }

    @Test func resetClearsPersistedSelection() {
        let suite = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let vm1 = PlaybackViewModel(defaults: suite)
        vm1.select(.pink)
        vm1.reset()
        let vm2 = PlaybackViewModel(defaults: suite)
        #expect(vm2.selection == .none)
        #expect(vm2.gains.allSatisfy { $0 == 0 })
    }

    @Test func freshDefaultsStartAtNone() {
        let vm = PlaybackViewModel(defaults: freshDefaults())
        #expect(vm.selection == .none)
    }

    @Test func masterVolumeDefaultsToFullAndPersists() {
        let d = freshDefaults()
        let vm = PlaybackViewModel(defaults: d)
        #expect(vm.masterVolume == 1.0)
        vm.masterVolume = 0.4
        let vm2 = PlaybackViewModel(defaults: d)
        #expect(abs(vm2.masterVolume - 0.4) < 0.001)
    }
}
