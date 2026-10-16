//
//  MCPClientConfiguration.swift
//  SimulatorManager
//

import Foundation
import SimulatorCore

/// The agents the Preferences window writes MCP setup for. Every client registers the same stdio
/// server, but each expects a different format.
enum MCPClient: String, CaseIterable, Identifiable {
    case claudeCode
    case vsCode
    case codex
    case genericJSON

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .claudeCode:
            "Claude Code"
        case .vsCode:
            "VS Code (GitHub Copilot)"
        case .codex:
            "Codex"
        case .genericJSON:
            "Cursor, Claude Desktop and others"
        }
    }

    /// Where the snippet goes.
    var instructions: String {
        switch self {
        case .claudeCode:
            "Run this in Terminal. It registers the server for every project."
        case .vsCode:
            "Add this to .vscode/mcp.json in a workspace, or run MCP: Open User Configuration. Copilot Chat lists the tools in Agent mode."
        case .codex:
            "Add this to ~/.codex/config.toml."
        case .genericJSON:
            "Add this to the client's MCP config, for example ~/.cursor/mcp.json or claude_desktop_config.json."
        }
    }
}

/// Builds ready-to-paste MCP client configs for the `simple-simulator-mcp` server.
///
/// Pure string building: the path and arguments go in, and every format escapes them for its own
/// syntax, so a path with spaces such as `Simulator Manager.app` survives in all of them.
struct MCPClientConfiguration: Equatable {
    /// The name every client lists the server under.
    static let serverName = "simple-simulator"

    let executablePath: String
    let arguments: [String]

    init(executablePath: String, allowUserDefaults: Bool, allowDestructive: Bool) {
        self.executablePath = executablePath
        self.arguments = MCPServerLaunch.arguments(allowUserDefaults: allowUserDefaults,
                                                   allowDestructive: allowDestructive)
    }

    func snippet(for client: MCPClient) -> String {
        switch client {
        case .claudeCode:
            claudeCodeCommand
        case .vsCode:
            vsCodeJSON
        case .codex:
            codexTOML
        case .genericJSON:
            genericJSON
        }
    }

    /// `claude mcp add`, user scope so the server is available in every project.
    var claudeCodeCommand: String {
        (["claude", "mcp", "add", "--scope", "user", Self.serverName, "--", executablePath] + arguments)
            .map(\.shellEscaped)
            .joined(separator: " ")
    }

    /// VS Code's `mcp.json`, which keys servers under `servers` rather than `mcpServers`.
    var vsCodeJSON: String {
        json(["servers": [Self.serverName: Server(type: "stdio", command: executablePath, args: arguments)]])
    }

    /// The one-line alternative for VS Code: `code --add-mcp` with the server as a JSON argument.
    var vsCodeAddCommand: String {
        let server = NamedServer(name: Self.serverName, command: executablePath, args: arguments)
        return "code --add-mcp " + singleQuoted(json(server, prettyPrinted: false))
    }

    /// Codex's `config.toml` table.
    var codexTOML: String {
        """
        [mcp_servers.\(Self.serverName)]
        command = \(tomlString(executablePath))
        args = [\(arguments.map(tomlString).joined(separator: ", "))]
        """
    }

    /// The `mcpServers` shape most other clients read.
    var genericJSON: String {
        json(["mcpServers": [Self.serverName: Server(type: nil, command: executablePath, args: arguments)]])
    }
}

private extension MCPClientConfiguration {
    struct Server: Encodable {
        let type: String?
        let command: String
        let args: [String]
    }

    struct NamedServer: Encodable {
        let name: String
        let command: String
        let args: [String]
    }

    func json(_ value: some Encodable, prettyPrinted: Bool = true) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted
            ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            : [.sortedKeys, .withoutEscapingSlashes]

        // Encoding plain strings and arrays cannot fail.
        guard let data = try? encoder.encode(value), let string = String(data: data, encoding: .utf8) else {
            return ""
        }

        return string
    }

    /// A TOML basic string: backslashes and double quotes escaped.
    func tomlString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        return "\"\(escaped)\""
    }

    /// Wraps `value` in single quotes for the shell; an embedded single quote closes the quoting,
    /// is escaped, and reopens it.
    func singleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
