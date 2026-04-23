// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ClawdPet",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ClawdPetApp", targets: ["ClawdPetApp"]),
        .executable(name: "ClawdPetHooks", targets: ["ClawdPetHooks"]),
        .executable(name: "ClawdPetSetup", targets: ["ClawdPetSetup"]),
        .library(name: "ClawdPetCore", targets: ["ClawdPetCore"])
    ],
    targets: [
        .target(
            name: "ClawdPetCore"
        ),
        .executableTarget(
            name: "ClawdPetApp",
            dependencies: ["ClawdPetCore"],
            resources: [
                .copy("Resources")
            ]
        ),
        .executableTarget(
            name: "ClawdPetHooks",
            dependencies: ["ClawdPetCore"]
        ),
        .executableTarget(
            name: "ClawdPetSetup",
            dependencies: ["ClawdPetCore"]
        ),
        .testTarget(
            name: "ClawdPetCoreTests",
            dependencies: ["ClawdPetCore"]
        )
    ]
)
