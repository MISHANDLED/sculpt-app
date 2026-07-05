import ProjectDescription

let project = Project(
    name: "Sculptor",
    packages: [
        .package(path: "Packages/AudioEngine"),
        .package(path: "Packages/DesignSystem")
    ],
    targets: [
        .target(
            name: "Sculptor",
            destinations: .iOS,
            product: .app,
            bundleId: "com.mishandled.sculptor",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .extendingDefault(with: [
                "UILaunchScreen": [:],
                "UIBackgroundModes": ["audio"]
            ]),
            sources: ["Sculptor/Sources/**"],
            dependencies: [
                .package(product: "AudioEngine"),
                .package(product: "DesignSystem")
            ]
        ),
        .target(
            name: "SculptorTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.mishandled.sculptor.tests",
            deploymentTargets: .iOS("17.0"),
            sources: ["Sculptor/Tests/**"],
            dependencies: [.target(name: "Sculptor")]
        )
    ]
)
