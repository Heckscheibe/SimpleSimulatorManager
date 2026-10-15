//
//  main.swift
//  simple-simulator-mcp
//
//  The logic lives in `SimulatorMCPServer.runCommandLine(arguments:)`, shared with the Xcode
//  target that embeds this executable in the app bundle.
//

import Foundation
import SimulatorMCPServer

exit(await SimulatorMCPServer.runCommandLine(arguments: Array(CommandLine.arguments.dropFirst())))
