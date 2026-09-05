//
//  ContainerShortcutHandling.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 25.08.26.
//

import Foundation

/// The menu actions a container shortcut offers: reveal it in Finder, copy its path, or — for
/// preferences — copy the content itself.
///
/// Both view models that drive the menu conform to it, so the app menu can be built once and reused
/// for the per-device apps list and the recent apps list.
@MainActor
protocol ContainerShortcutHandling: FolderOpening {
    var containerContent: ContainerContentCopying { get }
}

extension ContainerShortcutHandling {
    // MARK: - Apps
    func didSelectCopyPath(of shortcut: AppContainerShortcut, for app: any SimulatorApp) {
        didSelectCopyPath(of: shortcut.url(for: app))
    }

    /// - Parameter domain: A single defaults domain, or `nil` for every domain the app wrote.
    func didSelectCopyUserDefaultsJSON(for app: any SimulatorApp, domain: String? = nil) {
        guard let url = AppContainerShortcut.userDefaults.url(for: app) else {
            return
        }

        containerContent.copyUserDefaultsJSON(fromPreferencesDirectoryAt: url,
                                              ownDomain: app.bundleIdentifier,
                                              domain: domain,
                                              subject: app.displayName)
    }

    // MARK: - App Groups
    func didSelectCopyPath(of shortcut: AppGroupShortcut, for appGroup: AppGroup) {
        didSelectCopyPath(of: shortcut.url(for: appGroup))
    }

    func didSelectCopyUserDefaultsJSON(for appGroup: AppGroup, domain: String? = nil) {
        guard let url = AppGroupShortcut.userDefaults.url(for: appGroup) else {
            return
        }

        containerContent.copyUserDefaultsJSON(fromPreferencesDirectoryAt: url,
                                              ownDomain: appGroup.identifier,
                                              domain: domain,
                                              subject: "Group \(appGroup.name)")
    }

    // MARK: - Devices
    /// A shortcut whose URL cannot be derived is not offered in the menu; guarding here as well
    /// keeps a stale menu from copying nothing at all.
    func didSelectCopyPath(of url: URL?) {
        guard let url else {
            return
        }

        containerContent.copyPath(of: url)
    }
}
