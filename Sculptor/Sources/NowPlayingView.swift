import SwiftUI
import DesignSystem

struct NowPlayingView: View {
    @ObservedObject var vm: PlaybackViewModel

    var body: some View {
        ZStack {
            DockColor.background.ignoresSafeArea()

            VStack(spacing: DockSpacing.xl) {
                Spacer()

                PlayHeroButton(isPlaying: vm.isPlaying) { vm.togglePlay() }

                ScopeVisualizer(samples: vm.scopeSamples)
                    .frame(height: 80)
                    .padding(.horizontal, DockSpacing.xl)

                Text(vm.isPlaying ? "Playing · tap to pause" : "Paused")
                    .font(DockType.font(12))
                    .foregroundStyle(DockColor.textTertiary)

                if let err = vm.errorText {
                    Text(err).font(DockType.font(12)).foregroundStyle(.red)
                }

                Spacer()

                PresetChipsRow(vm: vm)
                    .padding(.bottom, DockSpacing.lg)
            }
            .padding(DockSpacing.xl)
        }
    }
}

#Preview {
    NowPlayingView(vm: PlaybackViewModel())
}
