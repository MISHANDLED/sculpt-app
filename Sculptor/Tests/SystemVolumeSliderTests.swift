import Testing
@testable import Sculptor
import MediaPlayer
import UIKit
import DesignSystem

@Suite struct SystemVolumeSliderTests {
    @Test func makeVolumeViewHasClearBackground() {
        let view = SystemVolumeSlider.makeVolumeView()
        #expect(view.backgroundColor == .clear)
    }

    @Test func makeVolumeViewTintsToAccentColor() {
        let view = SystemVolumeSlider.makeVolumeView()
        #expect(view.tintColor == UIColor(DockColor.accent))
    }
}
