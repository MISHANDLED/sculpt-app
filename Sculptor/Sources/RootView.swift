import SwiftUI
import DesignSystem

struct RootView: View {
    @StateObject private var vm = PlaybackViewModel()
    @State private var showSculpt = false
    @State private var showPresets = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        HomeView(
            vm: vm,
            onOpenSculpt: { showSculpt = true },
            onOpenPresets: { showPresets = true }
        )
        .sheet(isPresented: $showSculpt, onDismiss: {
            if vm.presetToRename != nil { showPresets = true }
        }) {
            SculptSheet(vm: vm)
        }
        .fullScreenCover(isPresented: $showPresets) {
            PresetsView(vm: vm)
        }
        .onChange(of: scenePhase) { _, phase in
            vm.setScopeActive(phase == .active)
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: CustomPreset.self, inMemory: true)
}
