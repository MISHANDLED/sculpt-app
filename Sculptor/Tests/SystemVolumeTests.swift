import Testing
import UIKit
import MediaPlayer
@testable import Sculptor

@Suite("System volume plumbing")
@MainActor
struct SystemVolumeTests {
    @Test func hiddenVolumeViewIsInvisibleAndInert() {
        let v = SystemVolume.makeHiddenVolumeView()
        #expect(v.alpha < 0.02)
        #expect(v.isUserInteractionEnabled == false)
    }

    @Test func findSliderLocatesNestedSlider() {
        let root = UIView()
        let mid = UIView()
        let slider = UISlider()
        mid.addSubview(slider)
        root.addSubview(mid)
        #expect(SystemVolume.findSlider(in: root) === slider)
    }

    @Test func findSliderReturnsNilWhenAbsent() {
        let root = UIView()
        root.addSubview(UIView())
        #expect(SystemVolume.findSlider(in: root) == nil)
    }

    @Test func levelStartsAtSessionOutputVolume() {
        let sv = SystemVolume()
        #expect(sv.level == AVAudioSession.sharedInstance().outputVolume)
    }
}
