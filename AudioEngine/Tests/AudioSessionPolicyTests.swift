import Testing
import AVFoundation
@testable import AudioEngine

@Test func interruptionBeganPauses() {
    #expect(interruptionAction(type: .began, options: [], wasPlaying: true) == .pause)
}

@Test func interruptionEndedResumesOnlyIfWasPlayingAndShouldResume() {
    #expect(interruptionAction(type: .ended, options: .shouldResume, wasPlaying: true) == .resume)
    #expect(interruptionAction(type: .ended, options: .shouldResume, wasPlaying: false) == .none)
    #expect(interruptionAction(type: .ended, options: [], wasPlaying: true) == .none)
}

@Test func routeChangePausesOnlyWhenOldDeviceGone() {
    #expect(routeChangeAction(reason: .oldDeviceUnavailable) == .pause)
    #expect(routeChangeAction(reason: .newDeviceAvailable) == .none)
    #expect(routeChangeAction(reason: .categoryChange) == .none)
}
