import MediaPlayer

/// Lock-screen / Control Center integration: publishes Now Playing metadata and
/// routes remote commands (lock screen, AirPods) back to the view model.
final class NowPlayingService {
    private let center = MPNowPlayingInfoCenter.default()
    private var targets: [(MPRemoteCommand, Any)] = []

    init(onPlay: @escaping () -> Void,
         onPause: @escaping () -> Void,
         onToggle: @escaping () -> Void) {
        let commands = MPRemoteCommandCenter.shared()
        addTarget(commands.playCommand, onPlay)
        addTarget(commands.pauseCommand, onPause)
        addTarget(commands.togglePlayPauseCommand, onToggle)
    }

    deinit {
        for (command, target) in targets { command.removeTarget(target) }
    }

    private func addTarget(_ command: MPRemoteCommand, _ handler: @escaping () -> Void) {
        let target = command.addTarget { _ in
            handler()
            return .success
        }
        targets.append((command, target))
    }

    func update(title: String, isPlaying: Bool) {
        center.nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: "Sculptor",
            MPNowPlayingInfoPropertyIsLiveStream: true,   // endless noise — no duration/seek bar
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
    }
}
