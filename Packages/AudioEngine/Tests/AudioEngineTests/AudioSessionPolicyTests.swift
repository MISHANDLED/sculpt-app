import Testing
import AVFoundation
@testable import AudioEngine

@Test func interruptionBeganPauses() {
    #expect(AudioSessionPolicy.interruptionAction(type: .began, options: [], wasPlaying: true) == .pause)
}

@Test func interruptionEndedResumesOnlyIfWasPlayingAndShouldResume() {
    #expect(AudioSessionPolicy.interruptionAction(type: .ended, options: .shouldResume, wasPlaying: true) == .resume)
    #expect(AudioSessionPolicy.interruptionAction(type: .ended, options: .shouldResume, wasPlaying: false) == .none)
    #expect(AudioSessionPolicy.interruptionAction(type: .ended, options: [], wasPlaying: true) == .none)
}

@Test func routeChangePausesOnlyWhenOldDeviceGone() {
    #expect(AudioSessionPolicy.routeChangeAction(reason: .oldDeviceUnavailable) == .pause)
    #expect(AudioSessionPolicy.routeChangeAction(reason: .newDeviceAvailable) == .none)
    #expect(AudioSessionPolicy.routeChangeAction(reason: .categoryChange) == .none)
}
