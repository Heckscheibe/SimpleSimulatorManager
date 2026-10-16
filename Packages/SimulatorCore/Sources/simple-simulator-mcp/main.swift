//
//  main.swift
//  simple-simulator-mcp
//
//  stdout carries the MCP protocol and nothing else: help, version and errors go to stderr.
//

import Foundation
import MCP
import SimulatorMCPServer

private func writeToStandardError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

switch LaunchCommand.parse(Array(CommandLine.arguments.dropFirst())) {
case let .run(options):
    let server = await SimulatorMCPServer.makeServer(options: options)
    try await server.start(transport: StdioTransport())
    await server.waitUntilCompleted()
case .version:
    writeToStandardError("\(SimulatorMCPServer.executableName) \(SimulatorMCPServer.version)")
case .help:
    writeToStandardError(LaunchCommand.usage)
case let .invalid(argument):
    writeToStandardError("Unknown argument \(argument).\n\n\(LaunchCommand.usage)")
    exit(EX_USAGE)
}
