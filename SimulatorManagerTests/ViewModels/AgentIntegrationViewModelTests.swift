import Foundation
import Testing
@testable import SimulatorManager

@Suite("Agent integration view model")
@MainActor
struct AgentIntegrationViewModelTests {
    private let executableURL = URL(fileURLWithPath: "/Applications/Simulator Manager.app/Contents/Helpers/simple-simulator-mcp")

    private func makeViewModel(pasteboard: MockPasteboard? = nil) -> AgentIntegrationViewModel {
        AgentIntegrationViewModel(pasteboard: pasteboard ?? MockPasteboard(), executableURL: executableURL)
    }

    @Test("Defaults to Claude Code with both opt-ins off")
    func defaults() {
        let viewModel = makeViewModel()

        #expect(viewModel.selectedClient == .claudeCode)
        #expect(viewModel.configuration.arguments.isEmpty)
        #expect(viewModel.snippet == viewModel.configuration.claudeCodeCommand)
    }

    @Test("Toggles change only the generated arguments")
    func togglesChangeArguments() {
        let viewModel = makeViewModel()
        let pathBefore = viewModel.configuration.executablePath

        viewModel.allowUserDefaults = true
        viewModel.allowDestructive = true
        viewModel.allowSnapshots = true

        #expect(viewModel.configuration.arguments == ["--allow-user-defaults", "--allow-destructive", "--allow-snapshots"])
        #expect(viewModel.configuration.executablePath == pathBefore)
    }

    @Test("Copy writes the selected client's snippet to the pasteboard", arguments: MCPClient.allCases)
    func copyWritesSnippet(client: MCPClient) {
        let pasteboard = MockPasteboard()
        let viewModel = makeViewModel(pasteboard: pasteboard)
        viewModel.selectedClient = client

        viewModel.copySnippet()

        #expect(pasteboard.lastWrittenString == viewModel.configuration.snippet(for: client))
        #expect(viewModel.isShowingCopiedConfirmation(for: viewModel.snippet))
    }

    @Test("The copied confirmation clears once the snippet changes")
    func copiedConfirmationFollowsSnippet() {
        let viewModel = makeViewModel()
        viewModel.copySnippet()

        viewModel.allowDestructive = true

        #expect(!viewModel.isShowingCopiedConfirmation(for: viewModel.snippet))
    }

    @Test("The code --add-mcp command is offered only for VS Code")
    func vsCodeAddCommandOnlyForVSCode() {
        let pasteboard = MockPasteboard()
        let viewModel = makeViewModel(pasteboard: pasteboard)

        #expect(viewModel.vsCodeAddCommand == nil)
        viewModel.copyVSCodeAddCommand()
        #expect(!pasteboard.didWrite)

        viewModel.selectedClient = .vsCode
        viewModel.copyVSCodeAddCommand()

        #expect(pasteboard.lastWrittenString == viewModel.configuration.vsCodeAddCommand)
    }

    @Test("A missing executable is reported as unavailable")
    func missingExecutable() {
        let viewModel = AgentIntegrationViewModel(pasteboard: MockPasteboard(),
                                                  executableURL: URL(fileURLWithPath: "/nonexistent/simple-simulator-mcp"))

        #expect(!viewModel.isExecutableAvailable)
    }
}
