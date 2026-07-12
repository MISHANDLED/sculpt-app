// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AudioEngine",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "AudioEngine", targets: ["AudioEngine"])
    ],
    targets: [
        .target(
            name: "RealtimeAtomics",
            path: "Sources/RealtimeAtomics",
            publicHeadersPath: "include"
        ),
        .target(
            name: "AudioEngine",
            dependencies: ["RealtimeAtomics"]
        ),
        .testTarget(
            name: "AudioEngineTests",
            dependencies: ["AudioEngine"]
        )
    ],
    swiftLanguageModes: [.v5]
)
