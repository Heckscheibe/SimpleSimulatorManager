//
//  ServerOptions.swift
//  SimulatorMCPServer
//

import Foundation
import SimulatorCore

/// What the agent opted into in its MCP config. Everything that is not opted into stays hidden.
public struct ServerOptions: Sendable, Equatable {
    public static let allowUserDefaultsFlag = MCPServerLaunch.allowUserDefaultsFlag
    public static let allowDestructiveFlag = MCPServerLaunch.allowDestructiveFlag

    /// Reading UserDefaults content, which can hold tokens or personal data.
    public let allowUserDefaults: Bool
    /// Erasing simulators and deleting cleanup candidates.
    public let allowDestructive: Bool

    public init(allowUserDefaults: Bool = false, allowDestructive: Bool = false) {
        self.allowUserDefaults = allowUserDefaults
        self.allowDestructive = allowDestructive
    }
}

/// The executable's command line, parsed apart from `main.swift` so it can be tested.
public enum LaunchCommand: Equatable, Sendable {
    case run(ServerOptions)
    case version
    case help
    case invalid(argument: String)

    public static let versionFlag = "--version"
    public static let helpFlags: Set<String> = ["--help", "-h"]

    /// - Parameter arguments: The arguments without the executable path.
    public static func parse(_ arguments: [String]) -> LaunchCommand {
        var allowUserDefaults = false
        var allowDestructive = false

        for argument in arguments {
            switch argument {
            case ServerOptions.allowUserDefaultsFlag:
                allowUserDefaults = true
            case ServerOptions.allowDestructiveFlag:
                allowDestructive = true
            case versionFlag:
                return .version
            case _ where helpFlags.contains(argument):
                return .help
            default:
                return .invalid(argument: argument)
            }
        }

        return .run(ServerOptions(allowUserDefaults: allowUserDefaults, allowDestructive: allowDestructive))
    }

    public static let usage = """
    Usage: \(SimulatorMCPServer.executableName) [\(ServerOptions.allowUserDefaultsFlag)] [\(ServerOptions.allowDestructiveFlag)]
    
    Model Context Protocol server over stdio that exposes the apps installed in local Apple
    simulators, their containers, app groups, recent installs and cleanup candidates.
    
    Options:
      \(ServerOptions.allowUserDefaultsFlag)  Enable read_user_defaults (UserDefaults may hold tokens or personal data)
      \(ServerOptions.allowDestructiveFlag)    Enable erase_device, erase_all_simulators and delete_cleanup_candidate
      \(versionFlag)              Print the version and exit
      -h, --help             Print this help and exit
    """
}
