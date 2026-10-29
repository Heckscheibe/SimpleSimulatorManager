//
//  AppGroup.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 14.03.24.
//

import Foundation

public class AppGroup {
    public var name: String {
        guard let index = identifier.firstIndex(of: ".") else {
            return ""
        }

        return String(identifier.suffix(from: identifier.index(after: index)))
    }

    public let identifier: String
    public let uuid: String

    /// Every defaults domain found in the shared container, suites included.
    public let userDefaultsDomains: [String]

    public var hasUserDefaults: Bool {
        !userDefaultsDomains.isEmpty
    }

    public var exportableUserDefaultsDomains: [String] {
        UserDefaultsDomain.appDomains(in: userDefaultsDomains, ownDomain: identifier)
    }

    public var url: URL?

    /// Whether this group belongs to the app with `bundleIdentifier`: the bundle identifier is the
    /// group's name or starts with it as a whole dot-separated prefix — so `group.com.example.notes`
    /// belongs to `com.example.notes` and `com.example.notes.widget`, but not to `com.example.notesplus`.
    public func belongs(toAppWithBundleIdentifier bundleIdentifier: String) -> Bool {
        !name.isEmpty && (bundleIdentifier == name || bundleIdentifier.hasPrefix(name + "."))
    }
    
    public init(
        identifier: String,
        uuid: String,
        userDefaultsDomains: [String],
        url: URL? = nil
    ) {
        self.identifier = identifier
        self.uuid = uuid
        self.userDefaultsDomains = userDefaultsDomains
        self.url = url
    }
}

extension AppGroup: Identifiable {
    public var id: String {
        identifier
    }
}

extension AppGroup {
    /// The groups that share a container with `app`, by the same rule discovery and the MCP server
    /// use — see ``belongs(toAppWithBundleIdentifier:)``. Snapshots need the answer per app, and
    /// the callers must not drift apart, so it lives here rather than in any one of them.
    static func groups(in appGroups: [AppGroup], associatedWith app: any SimulatorApp) -> [AppGroup] {
        appGroups.filter { $0.belongs(toAppWithBundleIdentifier: app.bundleIdentifier) }
    }
}
