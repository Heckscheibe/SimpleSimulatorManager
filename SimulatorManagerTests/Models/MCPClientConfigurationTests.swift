import Foundation
import Testing
@testable import SimulatorManager

@Suite("MCP client configuration")
struct MCPClientConfigurationTests {
    private let path = "/Applications/Simulator Manager.app/Contents/Helpers/simple-simulator-mcp"

    private func configuration(path: String? = nil, userDefaults: Bool = false, destructive: Bool = false) -> MCPClientConfiguration {
        MCPClientConfiguration(executablePath: path ?? self.path, allowUserDefaults: userDefaults, allowDestructive: destructive)
    }

    // MARK: - Arguments

    @Test("Flags map to launch arguments in a stable order", arguments: [
        (false, false, [String]()),
        (true, false, ["--allow-user-defaults"]),
        (false, true, ["--allow-destructive"]),
        (true, true, ["--allow-user-defaults", "--allow-destructive"])
    ])
    func argumentsFollowFlags(userDefaults: Bool, destructive: Bool, expected: [String]) {
        #expect(configuration(userDefaults: userDefaults, destructive: destructive).arguments == expected)
    }

    // MARK: - Claude Code

    @Test("Claude Code command registers the server in user scope with an escaped path")
    func claudeCodeCommand() {
        #expect(configuration().snippet(for: .claudeCode)
            == #"claude mcp add --scope user simple-simulator -- /Applications/Simulator\ Manager.app/Contents/Helpers/simple-simulator-mcp"#)
    }

    @Test("Claude Code command appends the flags after the executable")
    func claudeCodeCommandWithFlags() {
        #expect(configuration(userDefaults: true, destructive: true)
            .snippet(for: .claudeCode)
            .hasSuffix("simple-simulator-mcp --allow-user-defaults --allow-destructive"))
    }

    // MARK: - VS Code

    @Test("VS Code snippet uses the servers key with a stdio entry")
    func vsCodeJSON() throws {
        let object = try jsonObject(configuration(destructive: true).snippet(for: .vsCode))
        let servers = try #require(object["servers"] as? [String: Any])
        let server = try #require(servers["simple-simulator"] as? [String: Any])

        #expect(object["mcpServers"] == nil)
        #expect(server["type"] as? String == "stdio")
        #expect(server["command"] as? String == path)
        #expect(server["args"] as? [String] == ["--allow-destructive"])
    }

    @Test("VS Code add command passes the server as a single-quoted JSON argument")
    func vsCodeAddCommand() throws {
        let command = configuration(userDefaults: true).vsCodeAddCommand
        let prefix = "code --add-mcp '"

        #expect(command.hasPrefix(prefix))
        #expect(command.hasSuffix("'"))

        let object = try jsonObject(String(command.dropFirst(prefix.count).dropLast()))
        #expect(object["name"] as? String == "simple-simulator")
        #expect(object["command"] as? String == path)
        #expect(object["args"] as? [String] == ["--allow-user-defaults"])
    }

    @Test("VS Code add command keeps a single quote in the path intact for the shell")
    func vsCodeAddCommandEscapesSingleQuotes() {
        let command = configuration(path: "/Users/o'neil/Simulator Manager.app/Contents/Helpers/simple-simulator-mcp").vsCodeAddCommand

        #expect(command.contains(#"/Users/o'\''neil/"#))
    }

    // MARK: - Codex

    @Test("Codex snippet is a config.toml table")
    func codexTOML() {
        #expect(configuration(userDefaults: true).snippet(for: .codex) == """
        [mcp_servers.simple-simulator]
        command = "/Applications/Simulator Manager.app/Contents/Helpers/simple-simulator-mcp"
        args = ["--allow-user-defaults"]
        """)
    }

    @Test("Codex snippet escapes quotes and backslashes in the path")
    func codexTOMLEscapes() {
        let snippet = configuration(path: #"/tmp/a "quoted" \dir/simple-simulator-mcp"#).snippet(for: .codex)

        #expect(snippet.contains(#"command = "/tmp/a \"quoted\" \\dir/simple-simulator-mcp""#))
        #expect(snippet.contains("args = []"))
    }

    // MARK: - Generic JSON

    @Test("Generic snippet uses the mcpServers key without a type")
    func genericJSON() throws {
        let object = try jsonObject(configuration().snippet(for: .genericJSON))
        let servers = try #require(object["mcpServers"] as? [String: Any])
        let server = try #require(servers["simple-simulator"] as? [String: Any])

        #expect(server["command"] as? String == path)
        #expect((server["args"] as? [String])?.isEmpty == true)
        #expect(server["type"] == nil)
    }

    @Test("JSON snippets keep slashes unescaped so the path stays readable")
    func jsonKeepsSlashes() {
        #expect(configuration().snippet(for: .genericJSON).contains(path))
        #expect(configuration().snippet(for: .vsCode).contains(path))
    }

    private func jsonObject(_ string: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(string.utf8)) as? [String: Any])
    }
}
