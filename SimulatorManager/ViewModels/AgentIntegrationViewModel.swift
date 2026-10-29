//
//  AgentIntegrationViewModel.swift
//  SimulatorManager
//

import Foundation
import Observation
import SimulatorCore

/// Drives the "Agent Integration (MCP)" preferences section: where the embedded server lives and
/// the ready-to-paste config for each agent.
///
/// The opt-in toggles only change the generated snippet. They are deliberately not stored
/// settings: each agent decides for itself what it may do, in its own config.
@MainActor
@Observable
final class AgentIntegrationViewModel {
    @ObservationIgnored private let pasteboard: PasteboardWriting

    /// The `simple-simulator-mcp` executable inside the app bundle.
    let executableURL: URL

    /// False when the bundle carries no server, for example in a build that skipped embedding it.
    let isExecutableAvailable: Bool

    var selectedClient: MCPClient = .claudeCode
    var allowUserDefaults = false
    var allowDestructive = false
    var allowSnapshots = false

    /// The snippet most recently copied, so the view can confirm it until the input changes.
    private(set) var lastCopiedSnippet: String?

    init(
        pasteboard: PasteboardWriting = SystemPasteboard(),
        executableURL: URL = Bundle.main.bundleURL.appendingPathComponent(MCPServerLaunch.bundleRelativePath),
        fileManager: FileManager = .default
    ) {
        self.pasteboard = pasteboard
        self.executableURL = executableURL
        self.isExecutableAvailable = fileManager.isExecutableFile(atPath: executableURL.path)
    }

    var configuration: MCPClientConfiguration {
        MCPClientConfiguration(executablePath: executableURL.path,
                               allowUserDefaults: allowUserDefaults,
                               allowDestructive: allowDestructive,
                               allowSnapshots: allowSnapshots)
    }

    var snippet: String {
        configuration.snippet(for: selectedClient)
    }

    /// The `code --add-mcp` one-liner, offered alongside the `mcp.json` snippet for VS Code.
    var vsCodeAddCommand: String? {
        selectedClient == .vsCode ? configuration.vsCodeAddCommand : nil
    }

    func copySnippet() {
        copy(snippet)
    }

    func copyVSCodeAddCommand() {
        guard let vsCodeAddCommand else {
            return
        }

        copy(vsCodeAddCommand)
    }

    func isShowingCopiedConfirmation(for snippet: String) -> Bool {
        lastCopiedSnippet == snippet
    }
}

private extension AgentIntegrationViewModel {
    func copy(_ string: String) {
        pasteboard.write(string)
        lastCopiedSnippet = string
    }
}
