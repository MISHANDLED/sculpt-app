import ProjectDescription

let project = Project(
    name: "Sculptor",
    targets: [
        .target(
            name: "AudioEngine",
            destinations: .iOS,
            product: .framework,
            bundleId: "com.sculptor.audioengine",
            deploymentTargets: .iOS("17.0"),
            sources: ["AudioEngine/Sources/**"],
            dependencies: []
        ),
        .target(
            name: "AudioEngineTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.sculptor.audioengine.tests",
            deploymentTargets: .iOS("17.0"),
            sources: ["AudioEngine/Tests/**"],
            dependencies: [.target(name: "AudioEngine")]
        ),
        .target(
            name: "Sculptor",
            destinations: .iOS,
            product: .app,
            bundleId: "com.sculptor.app",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .extendingDefault(with: [
                "UILaunchScreen": [:]
            ]),
            sources: ["Sculptor/Sources/**"],
            dependencies: [.target(name: "AudioEngine")]
        )
    ]
)
