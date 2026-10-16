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
public enum AppContainerShortcut: String, CaseIterable, Identifiable, Sendable {
    case documents
    case appPackage
    case userDefaults

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .documents:
            "Documents Folder"
        case .appPackage:
            "App Package"
        case .userDefaults:
            "User Defaults"
        }
    }

    public func url(for app: any SimulatorApp) -> URL? {
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
    public static func available(for app: any SimulatorApp) -> [AppContainerShortcut] {
        allCases.filter { shortcut in
            guard shortcut.url(for: app) != nil else {
                return false
            }

            return shortcut != .userDefaults || app.hasUserDefaults
        }
    }
}

/// The same idea for an app group's shared container.
public enum AppGroupShortcut: String, CaseIterable, Identifiable, Sendable {
    case groupFolder
    case userDefaults

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .groupFolder:
            "Group Folder"
        case .userDefaults:
            "Group UserDefaults"
        }
    }

    public func url(for appGroup: AppGroup) -> URL? {
        switch self {
        case .groupFolder:
            appGroup.url
        case .userDefaults:
            appGroup.url?.appendingPathComponent(SimulatorPaths.userDefaultsPath)
        }
    }

    public static func available(for appGroup: AppGroup) -> [AppGroupShortcut] {
        allCases.filter { shortcut in
            guard shortcut.url(for: appGroup) != nil else {
                return false
            }

            return shortcut != .userDefaults || appGroup.hasUserDefaults
        }
    }
}
