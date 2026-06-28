import SwiftUI
import SwiftData
import AudioEngine
import DesignSystem

struct HomeView: View {
    @ObservedObject var vm: PlaybackViewModel
    let onOpenSculpt: () -> Void
    let onOpenPresets: () -> Void

    @Query(sort: \CustomPreset.sortIndex) private var customPresets: [CustomPreset]

    var body: some View {
        ZStack {
            DockColor.background.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()
                heroCenter
                Spacer()
                bottomRail
            }
        }
    }

    // MARK: - Sections

    private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("NOW PLAYING")
                    .font(DockType.font(10))
                    .foregroundStyle(DockColor.textTertiary)
                    .tracking(1.5)
                HStack(spacing: 8) {
                    Text(presetName)
                        .font(DockType.font(24, .semibold))
                        .foregroundStyle(DockColor.textPrimary)
                    if vm.isEdited {
                        Text("EDITED")
                            .font(DockType.font(10, .semibold))
                            .foregroundStyle(DockColor.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(DockColor.accent.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
            }
            Spacer()
            HStack(spacing: DockSpacing.sm) {
                Button(action: onOpenPresets) {
                    HStack(spacing: 4) {
                        Image(systemName: "bookmark")
                        Text("Presets")
                            .font(DockType.font(14, .medium))
                    }
                    .foregroundStyle(DockColor.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(DockColor.surface2)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(DockColor.border, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Menu {
                    Button { vm.cancelSleepTimer() } label: {
                        if vm.sleepMinutes == nil { Label("Off", systemImage: "checkmark") }
                        else { Text("Off") }
                    }
                    ForEach([15, 30, 45, 60], id: \.self) { mins in
                        Button { vm.startSleepTimer(minutes: mins) } label: {
                            if vm.sleepMinutes == mins { Label("\(mins) minutes", systemImage: "checkmark") }
                            else { Text("\(mins) minutes") }
                        }
                    }
                } label: {
                    moonLabel
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DockSpacing.xl)
    }

    private var heroCenter: some View {
        VStack(spacing: DockSpacing.lg) {
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
        }
    }

    private var bottomRail: some View {
        HStack(spacing: DockSpacing.md) {
            PresetChipsRow(vm: vm)
            Button(action: onOpenSculpt) {
                HStack(spacing: 6) {
                    Image(systemName: "slider.vertical.3")
                    Text("Sculpt")
                }
                .font(DockType.font(16, .semibold))
                .foregroundStyle(DockColor.background)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(DockColor.accent)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(DockSpacing.xl)
    }

    // MARK: - Helpers

    @ViewBuilder private var moonLabel: some View {
        if let remaining = vm.sleepRemaining {
            HStack(spacing: 4) {
                Image(systemName: "moon.fill")
                Text(formatCountdown(Int(remaining)))
                    .font(DockType.font(13, .medium))
                    .monospacedDigit()
            }
            .font(.system(size: 16))
            .foregroundStyle(DockColor.accent)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(DockColor.surface2)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(DockColor.border, lineWidth: 1))
        } else {
            Image(systemName: "moon")
                .font(.system(size: 16))
                .foregroundStyle(DockColor.textPrimary)
                .frame(width: 36, height: 36)
                .background(DockColor.surface2)
                .clipShape(Circle())
                .overlay(Circle().stroke(DockColor.border, lineWidth: 1))
        }
    }

    private var presetName: String {
        switch vm.selection {
        case .custom(let id):
            return customPresets.first(where: { $0.id == id })?.name ?? "Custom"
        default:
            let name = vm.presetDisplayName
            return name.isEmpty ? "Custom" : name
        }
    }
}

#Preview {
    HomeView(vm: PlaybackViewModel(), onOpenSculpt: {}, onOpenPresets: {})
        .modelContainer(for: CustomPreset.self, inMemory: true)
}
