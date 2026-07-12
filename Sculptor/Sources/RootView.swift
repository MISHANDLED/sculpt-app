import SwiftUI
import DesignSystem

struct RootView: View {
    @StateObject private var vm = PlaybackViewModel()
    @State private var showSculpt = false
    @State private var showPresets = false
    @Environment(\.scenePhase) private var scenePhase

    private var visualizationActive: Bool {
        VisualizationPolicy.isActive(
            sceneIsActive: scenePhase == .active,
            presetsPresented: showPresets
        )
    }

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
        .onChange(of: visualizationActive, initial: true) { _, active in
            vm.setVisualizationActive(active)
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: CustomPreset.self, inMemory: true)
}
