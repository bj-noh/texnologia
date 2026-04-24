// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TEXnologia",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TEXnologia", targets: ["TEXnologia"])
    ],
    targets: [
        .executableTarget(
            name: "TEXnologia",
            path: "TEXnologia",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
