//
//  AgentIntegrationSection.swift
//  SimulatorManager
//

import SwiftUI

/// The preferences section that sets up the bundled MCP server in an agent.
struct AgentIntegrationSection: View {
    @Bindable var viewModel: AgentIntegrationViewModel

    var body: some View {
        Section("Agent Integration (MCP)") {
            Text("""
            Coding agents can query simulators, installed apps and their containers through the \
            bundled MCP server. It runs only while an agent uses it, and opens no network port.
            """)
            .font(.callout)
            .foregroundStyle(.secondary)

            if !viewModel.isExecutableAvailable {
                Label("This build does not include the MCP server.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }

            // Stacked rather than LabeledContent: a path this long wraps into a ragged right-aligned
            // block beside the label.
            VStack(alignment: .leading, spacing: 4) {
                Text("Server")
                Text(viewModel.executableURL.path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 2) {
                Toggle("Allow reading UserDefaults", isOn: $viewModel.allowUserDefaults)
                Text("UserDefaults can hold tokens or personal data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Toggle("Allow destructive actions", isOn: $viewModel.allowDestructive)
                Text("Erasing simulators and deleting cleanup candidates.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("Agent", selection: $viewModel.selectedClient) {
                ForEach(MCPClient.allCases) { client in
                    Text(client.title).tag(client)
                }
            }

            SnippetView(text: viewModel.snippet,
                        caption: viewModel.selectedClient.instructions,
                        isCopied: viewModel.isShowingCopiedConfirmation(for: viewModel.snippet),
                        copy: viewModel.copySnippet)

            if let vsCodeAddCommand = viewModel.vsCodeAddCommand {
                SnippetView(text: vsCodeAddCommand,
                            caption: "Or add it from Terminal:",
                            isCopied: viewModel.isShowingCopiedConfirmation(for: vsCodeAddCommand),
                            copy: viewModel.copyVSCodeAddCommand)
            }
        }
    }
}

private struct SnippetView: View {
    let text: String
    let caption: String
    let isCopied: Bool
    let copy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(caption)
                .font(.callout)
                .foregroundStyle(.secondary)

            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

            HStack {
                Spacer()
                Button(isCopied ? "Copied" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc", action: copy)
            }
        }
    }
}
