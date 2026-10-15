//
//  SimulatorMCPServer.swift
//  SimulatorMCPServer
//

import Foundation
import MCP

/// Builds the MCP server agents talk to. Transport-agnostic: the executable runs it on
/// `StdioTransport`, tests on `InMemoryTransport`.
public enum SimulatorMCPServer {
    public static let name = "simple-simulator-manager"
    public static let executableName = "simple-simulator-mcp"
    /// The app's `MARKETING_VERSION`. fastlane's `release` lane rewrites this line when it bumps the
    /// version; `LaunchCommandTests` fails if the two ever drift.
    public static let version = "1.4.0"

    static let instructions = """
    Answers questions about the apps installed in local Apple simulators: where their data, \
    bundle and app-group containers are, what they wrote to UserDefaults, which apps were \
    installed recently and which simulators can be cleaned up. Tools take simulator UDIDs, \
    bundle identifiers, app group identifiers and cleanup candidate ids — call list_devices or \
    find_app first to look them up.
    """

    /// A server with the tool handlers registered, ready for `start(transport:)`.
    public static func makeServer(registry: ToolRegistry) async -> Server {
        let server = Server(
            name: name,
            version: version,
            title: "Simple Simulator Manager",
            instructions: instructions,
            capabilities: .init(tools: .init(listChanged: false))
        )

        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: registry.tools)
        }

        await server.withMethodHandler(CallTool.self) { parameters in
            await registry.call(parameters.name, arguments: parameters.arguments)
        }

        return server
    }

    public static func makeServer(options: ServerOptions) async -> Server {
        await makeServer(registry: ToolRegistry(options: options))
    }
}
