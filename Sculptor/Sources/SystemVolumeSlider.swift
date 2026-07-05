import SwiftUI
import MediaPlayer
import DesignSystem

/// Wraps `MPVolumeView`, the only sanctioned API for reading/writing the
/// device's system output volume and tracking the hardware volume buttons.
///
/// `MPVolumeView` renders empty/inert on the iOS Simulator — there is no
/// system-volume UI to draw there. Real behavior (slider thumb, hardware
/// button tracking) only appears on a physical device.
struct SystemVolumeSlider: UIViewRepresentable {
    /// Builds and configures the underlying `MPVolumeView`. Factored out as
    /// an internal static function so tests can exercise the configuration
    /// synchronously without needing a `UIViewRepresentableContext`.
    static func makeVolumeView() -> MPVolumeView {
        let view = MPVolumeView()
        view.backgroundColor = .clear
        view.tintColor = UIColor(DockColor.accent)
        return view
    }

    func makeUIView(context: Context) -> MPVolumeView {
        Self.makeVolumeView()
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
