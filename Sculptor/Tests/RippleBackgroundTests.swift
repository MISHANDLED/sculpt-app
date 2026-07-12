import AudioEngine
import Testing
@testable import Sculptor

@MainActor
@Suite("Ripple background")
struct RippleBackgroundTests {
    @Test func requiredInputsAreRetained() {
        let now = ContinuousClock().now
        let view = RippleBackground(
            snapshot: .zero,
            spectrumReceivedAt: now,
            isPlaying: true,
            masterVolume: 0.4,
            isActive: true
        )

        #expect(view.snapshot == .zero)
        #expect(view.spectrumReceivedAt == now)
        #expect(view.isPlaying)
        #expect(abs(view.masterVolume - 0.4) < 0.0001)
        #expect(view.isActive)
    }
}
