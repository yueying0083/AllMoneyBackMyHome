// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AMBH",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AMBHCore", targets: ["AMBHCore"]),
        .executable(name: "AMBH", targets: ["AMBH"])
    ],
    targets: [
        .target(
            name: "CCurlShim",
            linkerSettings: [.linkedLibrary("curl")]
        ),
        .target(
            name: "AMBHCore",
            dependencies: ["CCurlShim"]
        ),
        .executableTarget(
            name: "AMBH",
            dependencies: ["AMBHCore"]
        ),
        .testTarget(
            name: "AMBHCoreTests",
            dependencies: ["AMBHCore"]
        )
    ]
)
