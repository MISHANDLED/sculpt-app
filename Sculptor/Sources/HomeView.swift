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
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        ZStack {
            DockColor.background.ignoresSafeArea()

            RippleBackground(
                snapshot: vm.spectrumSnapshot,
                spectrumReceivedAt: vm.spectrumReceivedAt,
                isPlaying: vm.isPlaying,
                masterVolume: vm.masterVolume,
                isActive: vm.visualizationActive
            )
            .ignoresSafeArea()

            GeometryReader { proxy in
                layout(fold: activeDivision(in: proxy), in: proxy.size)
            }
        }
        .onChange(of: presetName, initial: true) { _, name in
            vm.nowPlayingTitle = name
        }
    }

    // MARK: - Layout

    /// iPhone Duo partially folded: keep play and knobs on opposite sides of
    /// the hinge. Compact height (closed Duo / iPhone landscape): side by side.
    @ViewBuilder
    private func layout(fold: CGRect?, in size: CGSize) -> some View {
        if let fold, fold.height > fold.width {
            sideBySide(
                leading: fold.minX,
                gap: fold.width,
                trailing: size.width - fold.maxX
            )
        } else if let fold {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    topBar
                    playButton.frame(maxHeight: .infinity)
                }
                .frame(height: max(0, fold.minY))
                VStack(spacing: 0) {
                    controls.frame(maxHeight: .infinity)
                    bottomRail
                }
                .padding(.top, fold.height)
            }
        } else if verticalSizeClass == .compact {
            sideBySide(leading: nil, gap: DockSpacing.xl * 2, trailing: nil)
        } else {
            VStack(spacing: 0) {
                topBar
                Spacer()
                VStack(spacing: DockSpacing.lg) {
                    playButton
                    controls
                }
                Spacer()
                bottomRail
            }
        }
    }

    private func sideBySide(
        leading: CGFloat?,
        gap: CGFloat,
        trailing: CGFloat?
    ) -> some View {
        VStack(spacing: 0) {
            topBar
            HStack(spacing: gap) {
                playButton.frame(width: leading.map { max(0, $0) })
                controls.frame(width: trailing.map { max(0, $0) })
            }
            .frame(maxHeight: .infinity)
            bottomRail
        }
    }

    private func activeDivision(in proxy: GeometryProxy) -> CGRect? {
        guard #available(iOS 27.1, *) else { return nil }
        return proxy.reservedRegions(kind: .division)
            .first(where: \.isActive)?.frame
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
                .accessibilityLabel("Presets")

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
                .accessibilityLabel("Sleep timer")
                .accessibilityValue(
                    vm.sleepRemaining.map {
                        SleepFormatting.countdown(Int($0)) + " remaining"
                    } ?? "Off"
                )
            }
            .fixedSize()
        }
        .padding(DockSpacing.xl)
    }

    private var playButton: some View {
        PlayHeroButton(isPlaying: vm.isPlaying) {
            vm.togglePlay()
        }
    }

    private var controls: some View {
        VStack(spacing: DockSpacing.lg) {
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
            PresetChipsRow(vm: vm, customPresets: customPresets)
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
