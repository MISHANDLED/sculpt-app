import SwiftUI
import DesignSystem

struct RootView: View {
    @StateObject private var vm = PlaybackViewModel()
    @State private var showSculpt = false
    @State private var showPresets = false

    var body: some View {
        HomeView(
            vm: vm,
            onOpenSculpt: { showSculpt = true },
            onOpenPresets: { showPresets = true },
            onOpenTimer: {}
        )
        .sheet(isPresented: $showSculpt) {
            SculptSheet(vm: vm)
        }
        .fullScreenCover(isPresented: $showPresets) {
            PresetsView(vm: vm)
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: CustomPreset.self, inMemory: true)
}
