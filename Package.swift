// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "sayit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "SayItCore", targets: ["SayItCore"]),
        .executable(name: "sayit", targets: ["SayItCLI"]),
        .executable(name: "SayItApp", targets: ["SayItApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/exPHAT/SwiftWhisper.git", revision: "c340197966ebd264f3135d3955874b40f8ed58bc"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.7.9"),
    ],
    targets: [
        .target(
            name: "SayItCore",
            dependencies: [
                .product(name: "SwiftWhisper", package: "SwiftWhisper"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "SayItCLI",
            dependencies: ["SayItCore"]
        ),
        .executableTarget(
            name: "SayItApp",
            dependencies: ["SayItCore"]
        ),
        .testTarget(
            name: "SayItCoreTests",
            dependencies: ["SayItCore"]
        )
    ]
)
