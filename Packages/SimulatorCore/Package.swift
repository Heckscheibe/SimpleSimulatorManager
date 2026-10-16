// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SimulatorCore",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "SimulatorCore", targets: ["SimulatorCore"])
    ],
    targets: [
        .target(name: "SimulatorCore"),
        .testTarget(name: "SimulatorCoreTests", dependencies: ["SimulatorCore"])
    ]
)
