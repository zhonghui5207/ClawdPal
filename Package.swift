// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ClawdPal",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ClawdPalApp", targets: ["ClawdPalApp"]),
        .executable(name: "ClawdPalHooks", targets: ["ClawdPalHooks"]),
        .executable(name: "ClawdPalSetup", targets: ["ClawdPalSetup"]),
        .library(name: "ClawdPalCore", targets: ["ClawdPalCore"])
    ],
    targets: [
        .target(
            name: "ClawdPalCore"
        ),
        .executableTarget(
            name: "ClawdPalApp",
            dependencies: ["ClawdPalCore"],
            resources: [
                .copy("Resources")
            ]
        ),
        .executableTarget(
            name: "ClawdPalHooks",
            dependencies: ["ClawdPalCore"]
        ),
        .executableTarget(
            name: "ClawdPalSetup",
            dependencies: ["ClawdPalCore"]
        ),
        .testTarget(
            name: "ClawdPalCoreTests",
            dependencies: ["ClawdPalCore"]
        )
    ]
)
