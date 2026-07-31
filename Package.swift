// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SayIt",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(url: "https://github.com/MrKai77/DynamicNotchKit", from: "1.0.0"),
        .package(url: "https://github.com/exPHAT/SwiftWhisper.git", from: "1.2.0"),
        .package(
            url: "https://github.com/FluidInference/FluidAudio.git",
            .upToNextMinor(from: "0.12.6")
        ),
    ],
    targets: [
        .executableTarget(
            name: "SayIt",
            dependencies: [
                "DynamicNotchKit",
                "SwiftWhisper",
                "FluidAudio",
            ],
            path: "Sources/SayIt",
            resources: [
                .process("Assets.xcassets"),
                .process("Resources"),
            ]
        ),
    ]
)
