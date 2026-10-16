//
//  main.swift
//  SimulatorManagerMCP
//
//  Builds the copy of `simple-simulator-mcp` that ships in the app bundle (`Contents/Helpers`).
//  The logic lives in `SimulatorMCPServer.runCommandLine(arguments:)`, shared with the package executable.
//

import Foundation
import SimulatorMCPServer

exit(await SimulatorMCPServer.runCommandLine(arguments: Array(CommandLine.arguments.dropFirst())))
