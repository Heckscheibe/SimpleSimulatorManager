//
//  OpenPreferencesButton.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 12.08.26.
//

import AppKit
import SwiftUI

/// Menu entry that opens the preferences window.
///
/// Used instead of `SettingsLink`, which does not work in this app — see ``PreferencesWindow`` for
/// why. The app is activated explicitly because an agent app is not brought to the front on its
/// own, so the window would otherwise open behind whatever the user was working in.
struct OpenPreferencesButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Settings…") {
            openWindow(id: PreferencesWindow.identifier)
            NSApp.activate()
        }
        .keyboardShortcut(",")
    }
}
