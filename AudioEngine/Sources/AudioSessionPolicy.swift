import AVFoundation

public enum InterruptionAction: Equatable { case pause, resume, none }

/// Pure decision for an AVAudioSession interruption notification.
public func interruptionAction(
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

public enum RouteAction: Equatable { case pause, none }

/// Pure decision for an AVAudioSession route-change notification.
public func routeChangeAction(reason: AVAudioSession.RouteChangeReason) -> RouteAction {
    reason == .oldDeviceUnavailable ? .pause : .none
}
