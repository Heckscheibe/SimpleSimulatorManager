//
//  CommandLineEntryPoint.swift
//  SimulatorMCPServer
//
//  Shared by the package's `simple-simulator-mcp` executable and the Xcode target that ships the
//  same binary inside the app bundle, so both behave identically.
//
//  stdout carries the MCP protocol and nothing else: help, version and errors go to stderr.
//

import Foundation
import MCP

public extension SimulatorMCPServer {
    /// Parses the launch arguments and either serves MCP over stdio until the client disconnects,
    /// or prints help or the version.
    /// - Parameter arguments: The arguments without the executable path.
    /// - Returns: The process exit code.
    static func runCommandLine(arguments: [String]) async -> Int32 {
        switch LaunchCommand.parse(arguments) {
        case let .run(options):
            let server = await makeServer(options: options)
            do {
                try await server.start(transport: StdioTransport())
            } catch {
                writeToStandardError("Failed to start the MCP server: \(error.localizedDescription)")
                return EXIT_FAILURE
            }
            await server.waitUntilCompleted()
            return EXIT_SUCCESS
        case .version:
            writeToStandardError("\(executableName) \(version)")
            return EXIT_SUCCESS
        case .help:
            writeToStandardError(LaunchCommand.usage)
            return EXIT_SUCCESS
        case let .invalid(argument):
            writeToStandardError("Unknown argument \(argument).\n\n\(LaunchCommand.usage)")
            return EX_USAGE
        }
    }
}

private func writeToStandardError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}
