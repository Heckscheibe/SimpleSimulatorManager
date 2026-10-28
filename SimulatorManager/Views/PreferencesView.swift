//
//  PreferencesView.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 11.08.26.
//

import AppKit
import SwiftUI

/// Identifies the preferences window scene.
///
/// A plain SwiftUI `Settings` scene is not usable here: this app is an agent (`LSUIElement`) whose
/// only other scene is a `MenuBarExtra`, and in that configuration the `Settings` scene accepts the
/// `showSettingsWindow:` action — `NSApp.sendAction` returns `true` — without ever creating a
/// window, so `SettingsLink` and ⌘, silently do nothing. An explicit `Window` scene opened through
/// `openWindow` behaves correctly.
enum PreferencesWindow {
    static let identifier = "preferences"

    /// Opens the window from the menu bar panel, and closes the panel.
    ///
    /// The order is the point. Activating is only a request on current macOS, and it is granted
    /// while the user is still interacting with the app — that is, while the panel they clicked in is
    /// up. Closing the panel first gave that up: the window was created, but behind whatever app was
    /// in front, so clicking Settings… appeared to do nothing until a later click happened to win.
    /// Once the window is in front and key the panel would close itself anyway; dismissing it
    /// afterwards only covers the case where it did not.
    @MainActor
    static func openFromPanel(activate: () -> Void, openWindow: () -> Void, dismissPanel: () -> Void) {
        activate()
        openWindow()
        dismissPanel()
    }
}

/// Contents of the settings window.
///
/// The menu keeps its own quick toggles; this window is the place for preferences that cannot be
/// expressed as a menu item, such as the shortcut recorder. Both surfaces observe the same
/// ``Settings`` instance, so they always agree.
struct PreferencesView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var shortcutController: GlobalShortcutController
    let recorderViewModel: ShortcutRecorderViewModel
    let agentIntegrationViewModel: AgentIntegrationViewModel

    var body: some View {
        Form {
            Section("Global Shortcut") {
                LabeledContent("Open menu") {
                    ShortcutRecorderView(viewModel: recorderViewModel)
                }

                if let validationMessage = recorderViewModel.validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }

                if let registrationErrorMessage = shortcutController.registrationErrorMessage {
                    Label(registrationErrorMessage, systemImage: "exclamationmark.octagon")
                        .foregroundStyle(.red)
                        .font(.callout)
                }

                Text("Press the shortcut anywhere to open the menu. Once open, use the arrow keys to navigate and return to select.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Menu Contents") {
                Toggle("Recent Apps", isOn: settings.binding(for: \.showRecentApps))
                Toggle("iOS", isOn: settings.binding(for: \.showIOS))
                Toggle("iPadOS", isOn: settings.binding(for: \.showIPadOS))
                Toggle("watchOS", isOn: settings.binding(for: \.showWatchOS))
                Toggle("tvOS", isOn: settings.binding(for: \.showTVOS))
                Toggle("visionOS", isOn: settings.binding(for: \.showVisionOS))
                Toggle("UI Test Runner Apps", isOn: settings.binding(for: \.showTestRunnerApps))
            }

            AgentIntegrationSection(viewModel: agentIntegrationViewModel)
        }
        .formStyle(.grouped)
        // With the agent integration snippets the content is taller than a laptop screen, so the
        // window no longer fits it exactly: it opens at a comfortable height, the form scrolls,
        // and the window can be resized vertically.
        .frame(width: 460)
        .frame(minHeight: 360, idealHeight: 640, maxHeight: .infinity)
        .onAppear {
            // The app is an agent (LSUIElement), so it is not activated automatically and the
            // settings window would otherwise open behind whatever the user was working in.
            NSApp.activate()
        }
    }
}
