//
//  AppShortcutMenuItems.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 25.08.26.
//

import Foundation
import SwiftUI

/// The shortcuts offered for a single app, shared by the per-device apps list and the recent apps
/// list so both stay in sync.
struct AppShortcutMenuItems<Actions: ContainerShortcutHandling>: View {
    let app: any SimulatorApp
    let actions: Actions

    var body: some View {
        ForEach(AppContainerShortcut.available(for: app)) { shortcut in
            Button {
                actions.didSelectFolder(shortcut, for: app)
            } label: {
                Text(shortcut.title)
            }
        }

        Divider()

        Menu("Copy Path") {
            ForEach(AppContainerShortcut.available(for: app)) { shortcut in
                Button {
                    actions.didSelectCopyPath(of: shortcut, for: app)
                } label: {
                    Text(shortcut.title)
                }
            }
        }

        UserDefaultsCopyMenuItems(domains: app.exportableUserDefaultsDomains) { domain in
            actions.didSelectCopyUserDefaultsJSON(for: app, domain: domain)
        }
    }
}
