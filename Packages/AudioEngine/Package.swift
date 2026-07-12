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
            publicHeadersPath: "include",
            cSettings: [.unsafeFlags(["-fno-objc-arc"])],
            linkerSettings: [.linkedFramework("AVFAudio")]
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
