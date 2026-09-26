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
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.4"),
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", revision: "01dec7c9bdce3088a6b6b7ab9f2e403458195efb"),
        .package(url: "https://github.com/ml-explore/mlx-swift.git", exact: "0.31.4"),
    ],
    targets: [
        .executableTarget(
            name: "SayIt",
            dependencies: [
                "DynamicNotchKit",
                "SwiftWhisper",
                "FluidAudio",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
                .product(name: "MLX", package: "mlx-swift"),
            ],
            path: "Sources/SayIt",
            resources: [
                .process("Assets.xcassets"),
                .process("Resources"),
            ]
        ),
    ]
)
