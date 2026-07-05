import ProjectDescription

let project = Project(
    name: "Sculptor",
    packages: [
        .package(path: "Packages/AudioEngine")
    ],
    targets: [
        .target(
            name: "DesignSystem",
            destinations: .iOS,
            product: .framework,
            bundleId: "com.mishandled.sculptor.designsystem",
            deploymentTargets: .iOS("17.0"),
            sources: ["DesignSystem/Sources/**"],
            resources: ["DesignSystem/Resources/**"],
            dependencies: []
        ),
        .target(
            name: "DesignSystemTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.mishandled.sculptor.designsystem.tests",
            deploymentTargets: .iOS("17.0"),
            sources: ["DesignSystem/Tests/**"],
            dependencies: [.target(name: "DesignSystem")]
        ),
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
                .target(name: "DesignSystem")
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
