//
//  ContainerShortcut.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 25.08.26.
//

import Foundation

/// A folder inside an app's simulator container that the menu offers a shortcut to.
///
/// Opening the folder in Finder and copying its path have to agree on which URL a shortcut points
/// at, so the derivation lives here instead of in the individual actions.
enum AppContainerShortcut: String, CaseIterable, Identifiable {
    case documents
    case appPackage
    case userDefaults

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .documents:
            "Documents Folder"
        case .appPackage:
            "App Package"
        case .userDefaults:
            "User Defaults"
        }
    }

    func url(for app: any SimulatorApp) -> URL? {
        switch self {
        case .documents:
            app.appDocumentsFolderURL
        case .appPackage:
            // `appPackageURL` is the `.app` bundle itself; the shortcut opens the container folder
            // holding it, which is what the Finder action has always done.
            app.appPackageURL?.deletingLastPathComponent()
        case .userDefaults:
            app.appDocumentsFolderURL?.appendingPathComponent(SimulatorPaths.userDefaultsPath)
        }
    }

    /// Shortcuts that can actually be resolved for `app`, so no menu item leads nowhere.
    ///
    /// `Library/Preferences` only exists once an app has written preferences, which discovery
    /// already determined — no second filesystem check here.
    static func available(for app: any SimulatorApp) -> [AppContainerShortcut] {
        allCases.filter { shortcut in
            guard shortcut.url(for: app) != nil else {
                return false
            }

            return shortcut != .userDefaults || app.hasUserDefaults
        }
    }
}

/// The same idea for an app group's shared container.
enum AppGroupShortcut: String, CaseIterable, Identifiable {
    case groupFolder
    case userDefaults

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .groupFolder:
            "Group Folder"
        case .userDefaults:
            "Group UserDefaults"
        }
    }

    func url(for appGroup: AppGroup) -> URL? {
        switch self {
        case .groupFolder:
            appGroup.url
        case .userDefaults:
            appGroup.url?.appendingPathComponent(SimulatorPaths.userDefaultsPath)
        }
    }

    static func available(for appGroup: AppGroup) -> [AppGroupShortcut] {
        allCases.filter { shortcut in
            guard shortcut.url(for: appGroup) != nil else {
                return false
            }

            return shortcut != .userDefaults || appGroup.hasUserDefaults
        }
    }
}
