import AVFoundation
import MediaPlayer
import SwiftUI

/// System (hardware) volume bridge. Reads via KVO on the audio session's
/// outputVolume; writes via the UISlider inside a hidden MPVolumeView —
/// the only sanctioned way to set system volume. If iOS ever stops
/// exposing that slider, setLevel degrades to a no-op and the knob
/// becomes display-only.
@MainActor
final class SystemVolume: ObservableObject {
    @Published private(set) var level: Float

    /// Host must keep this view in the window hierarchy for setLevel to work.
    let volumeView = SystemVolume.makeHiddenVolumeView()

    private var observation: NSKeyValueObservation?

    init() {
        let session = AVAudioSession.sharedInstance()
        level = session.outputVolume
        observation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let v = change.newValue else { return }
            Task { @MainActor [weak self] in self?.level = v }
        }
    }

    func setLevel(_ v: Float) {
        let clamped = min(1, max(0, v))
        level = clamped
        Self.findSlider(in: volumeView)?.value = clamped
    }

    static func makeHiddenVolumeView() -> MPVolumeView {
        let v = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        v.alpha = 0.01          // 0 can make iOS skip layout of the slider
        v.isUserInteractionEnabled = false
        v.clipsToBounds = true
        return v
    }

    static func findSlider(in view: UIView) -> UISlider? {
        if let slider = view as? UISlider { return slider }
        for sub in view.subviews {
            if let found = findSlider(in: sub) { return found }
        }
        return nil
    }
}

/// Keeps the hidden MPVolumeView alive in the hierarchy behind Home.
struct HiddenVolumeHost: UIViewRepresentable {
    let volume: SystemVolume

    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: .zero)
        container.addSubview(volume.volumeView)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
