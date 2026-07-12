import SwiftUI
import SwiftData
import AudioEngine
import DesignSystem

struct HomeView: View {
    @ObservedObject var vm: PlaybackViewModel
    let onOpenSculpt: () -> Void
    let onOpenPresets: () -> Void

    @Query(sort: \CustomPreset.sortIndex) private var customPresets: [CustomPreset]
    @StateObject private var systemVolume = SystemVolume()

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
        .onChange(of: presetName, initial: true) { _, name in
            vm.nowPlayingTitle = name
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
                        .lineLimit(2)
                        .truncationMode(.tail)
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
                    Image(systemName: "bookmark")
                        .font(.system(size: 16))
                        .foregroundStyle(DockColor.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(DockColor.surface2)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(DockColor.border, lineWidth: 1))
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
            .fixedSize()
        }
        .padding(DockSpacing.xl)
    }

    private var heroCenter: some View {
        VStack(spacing: DockSpacing.lg) {
            PlayHeroButton(isPlaying: vm.isPlaying) {
                vm.togglePlay()
            }

            HStack(spacing: DockSpacing.xl * 2) {
                VolumeKnob(
                    value: $vm.masterVolume,
                    icon: "speaker.wave.2.fill",
                    label: "NOISE"
                )
                VolumeKnob(
                    value: Binding(
                        get: { systemVolume.level },
                        set: { systemVolume.setLevel($0) }
                    ),
                    icon: "iphone",
                    label: "PHONE"
                )
            }
            .background(
                HiddenVolumeHost(volume: systemVolume)
                    .frame(width: 1, height: 1)
            )

            Text(vm.isPlaying ? "Playing · tap to pause" : "Paused")
                .font(DockType.font(12))
                .foregroundStyle(DockColor.textTertiary)

            if let err = vm.errorText {
                Text(err)
                    .font(DockType.font(12))
                    .foregroundStyle(.red)
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
                .font(DockType.font(14, .semibold))
                .foregroundStyle(DockColor.background)
                .padding(.horizontal, DockSpacing.lg)
                .padding(.vertical, DockSpacing.sm)
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
                Text(SleepFormatting.countdown(Int(remaining)))
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
