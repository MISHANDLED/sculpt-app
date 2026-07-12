import AVFoundation
import Foundation
import Testing
@testable import AudioEngine

@MainActor
@Suite("Session deactivation policy")
struct NoiseEngineSessionTests {

    @Test func manualStopDeactivatesSession() {
        let engine = NoiseEngine()
        engine.stop()
        #expect(engine._lastStopDeactivatedSession == true)
    }

    @Test func interruptionStopKeepsSessionActive() {
        let engine = NoiseEngine()
        engine._applyInterruption(type: .began, options: [])
        #expect(engine._lastStopDeactivatedSession == false)
    }

    @Test func routeNotificationHopsToMainActor() async {
        let center = NotificationCenter()
        let engine = NoiseEngine(notificationCenter: center)
        engine._setPlayingForTesting(true)

        await Task.detached {
            center.post(
                name: AVAudioSession.routeChangeNotification,
                object: nil,
                userInfo: [
                    AVAudioSessionRouteChangeReasonKey:
                        AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
                ]
            )
        }.value
        for _ in 0..<20 where engine.isPlaying { await Task.yield() }
        #expect(!engine.isPlaying)
        #expect(engine._lastStopDeactivatedSession == true)
    }
}
