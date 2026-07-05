import AVFoundation

public enum InterruptionAction: Equatable { case pause, resume, none }
public enum RouteAction: Equatable { case pause, none }

/// Pure decisions for AVAudioSession notifications.
public enum AudioSessionPolicy {
    /// Decision for an interruption notification.
    public static func interruptionAction(
        type: AVAudioSession.InterruptionType,
        options: AVAudioSession.InterruptionOptions,
        wasPlaying: Bool
    ) -> InterruptionAction {
        switch type {
        case .began:
            return .pause
        case .ended:
            return (options.contains(.shouldResume) && wasPlaying) ? .resume : .none
        @unknown default:
            return .none
        }
    }

    /// Decision for a route-change notification.
    public static func routeChangeAction(reason: AVAudioSession.RouteChangeReason) -> RouteAction {
        reason == .oldDeviceUnavailable ? .pause : .none
    }
}
