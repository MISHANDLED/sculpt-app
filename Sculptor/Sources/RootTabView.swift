import SwiftUI
import DesignSystem

enum AppTab: CaseIterable {
    case nowPlaying, sculpt, presets

    var title: String {
        switch self {
        case .nowPlaying: return "Now Playing"
        case .sculpt:     return "Sculpt"
        case .presets:    return "Presets"
        }
    }

    var systemImage: String {
        switch self {
        case .nowPlaying: return "play.circle"
        case .sculpt:     return "slider.vertical.3"
        case .presets:    return "bookmark"
        }
    }
}

struct RootTabView: View {
    @StateObject private var vm = PlaybackViewModel()
    @State private var selection: AppTab = .nowPlaying

    var body: some View {
        TabView(selection: $selection) {
            NowPlayingView(vm: vm)
                .tabItem { Label(AppTab.nowPlaying.title, systemImage: AppTab.nowPlaying.systemImage) }
                .tag(AppTab.nowPlaying)
            SculptView(vm: vm)
                .tabItem { Label(AppTab.sculpt.title, systemImage: AppTab.sculpt.systemImage) }
                .tag(AppTab.sculpt)
            PresetsPlaceholderView()
                .tabItem { Label(AppTab.presets.title, systemImage: AppTab.presets.systemImage) }
                .tag(AppTab.presets)
        }
        .tint(DockColor.accent)
    }
}

#Preview { RootTabView() }
