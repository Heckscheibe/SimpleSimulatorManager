// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SimulatorCore",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "SimulatorCore", targets: ["SimulatorCore"]),
        .library(name: "SimulatorMCPServer", targets: ["SimulatorMCPServer"]),
        .executable(name: "simple-simulator-mcp", targets: ["simple-simulator-mcp"])
    ],
    dependencies: [
        // Pre-1.0: minor releases can break the API, so the version is pinned exactly.
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1")
    ],
    targets: [
        .target(name: "SimulatorCore"),
        .target(
            name: "SimulatorMCPServer",
            dependencies: [
                "SimulatorCore",
                .product(name: "MCP", package: "swift-sdk")
            ]
        ),
        .executableTarget(
            name: "simple-simulator-mcp",
            dependencies: [
                "SimulatorMCPServer",
                .product(name: "MCP", package: "swift-sdk")
            ]
        ),
        .testTarget(name: "SimulatorCoreTests", dependencies: ["SimulatorCore"]),
        .testTarget(
            name: "SimulatorMCPServerTests",
            dependencies: [
                "SimulatorMCPServer",
                "SimulatorCore",
                .product(name: "MCP", package: "swift-sdk")
            ]
        )
    ]
)
