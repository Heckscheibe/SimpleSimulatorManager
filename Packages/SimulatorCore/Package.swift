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
            dependencies: ["SimulatorMCPServer"]
        ),
        // Fixtures shared by the test targets; not part of any product.
        .target(
            name: "SimulatorCoreTestSupport",
            dependencies: ["SimulatorCore"],
            path: "Tests/SimulatorCoreTestSupport"
        ),
        .testTarget(name: "SimulatorCoreTests", dependencies: ["SimulatorCore", "SimulatorCoreTestSupport"]),
        .testTarget(
            name: "SimulatorMCPServerTests",
            dependencies: [
                "SimulatorMCPServer",
                "SimulatorCore",
                "SimulatorCoreTestSupport",
                .product(name: "MCP", package: "swift-sdk")
            ]
        )
    ]
)
