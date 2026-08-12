//
//  PreferencesView.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 11.08.26.
//

import AppKit
import SwiftUI

/// Contents of the settings window.
///
/// The menu keeps its own quick toggles; this window is the place for preferences that cannot be
/// expressed as a menu item, such as the shortcut recorder. Both surfaces observe the same
/// ``Settings`` instance, so they always agree.
struct PreferencesView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var shortcutController: GlobalShortcutController
    let recorderViewModel: ShortcutRecorderViewModel

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
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            // The app is an agent (LSUIElement), so it is not activated automatically and the
            // settings window would otherwise open behind whatever the user was working in.
            NSApp.activate()
        }
    }
}
