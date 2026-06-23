import SwiftUI
import AudioEngine

struct RootView: View {
    @StateObject private var vm = SpikeViewModel()

    var body: some View {
        VStack(spacing: 24) {
            Text("Phase 0 — Noise Spike").font(.headline)

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<8, id: \.self) { i in
                    VStack(spacing: 6) {
                        Slider(
                            value: Binding(
                                get: { vm.gains[i] },
                                set: { vm.setGain(band: i, dB: $0) }
                            ),
                            in: -24...12
                        )
                        .frame(width: 150)               // track length (visual height once rotated)
                        .rotationEffect(.degrees(-90))
                        .frame(width: 34, height: 150)   // narrow layout footprint so 8 fit on screen
                        Text(label(vm.frequencies[i]))
                            .font(.caption2)
                            .fixedSize()                 // keep "250" on one line
                    }
                }
            }
            .frame(height: 190)

            HStack(spacing: 12) {
                Button("White") { vm.apply(.white) }
                Button("Pink") { vm.apply(.pink) }
                Button("Brown") { vm.apply(.brown) }
            }
            .buttonStyle(.bordered)

            Button(vm.isPlaying ? "Pause" : "Play") { vm.togglePlay() }
                .font(.title)
                .buttonStyle(.borderedProminent)

            if let err = vm.errorText {
                Text(err).font(.footnote).foregroundStyle(.red)
            }
        }
        .padding()
    }

    private func label(_ f: Float) -> String {
        f >= 1000 ? "\(Int(f / 1000))k" : "\(Int(f))"
    }
}
