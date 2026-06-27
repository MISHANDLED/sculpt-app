import Testing
@testable import Sculptor

@Test func appTabHasThreeTabsWithTitles() {
    #expect(AppTab.allCases.count == 3)
    #expect(AppTab.nowPlaying.title == "Now Playing")
    #expect(AppTab.sculpt.title == "Sculpt")
    #expect(AppTab.presets.title == "Presets")
}

@Test func appTabSystemImages() {
    #expect(AppTab.nowPlaying.systemImage == "play.circle")
    #expect(AppTab.sculpt.systemImage == "slider.vertical.3")
    #expect(AppTab.presets.systemImage == "bookmark")
}
