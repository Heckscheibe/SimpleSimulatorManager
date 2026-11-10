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

    /// Whether this group shares a container with `app` — the one association rule discovery,
    /// snapshots and the MCP server all use.
    ///
    /// When discovery could read the app's entitlements, the group belongs to it exactly when its
    /// `com.apple.security.application-groups` lists the group's identifier, however the group is
    /// named: `group.com.example.notes.shared` belongs to `com.example.notes` if the app claims it,
    /// and a parent group such as `group.com.example` belongs only to the sibling apps that claim it.
    ///
    /// When they could not be read, the name decides: the bundle identifier is the group's name or
    /// starts with it as a whole dot-separated prefix — so `group.com.example.notes` belongs to
    /// `com.example.notes` and `com.example.notes.widget`, but not to `com.example.notesplus`.
    public func belongs(to app: any SimulatorApp) -> Bool {
        if let applicationGroupIdentifiers = app.applicationGroupIdentifiers {
            return applicationGroupIdentifiers.contains(identifier)
        }

        return !name.isEmpty && (app.bundleIdentifier == name || app.bundleIdentifier.hasPrefix(name + "."))
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
    /// use — see ``belongs(to:)``. Snapshots need the answer per app, and
    /// the callers must not drift apart, so it lives here rather than in any one of them.
    static func groups(in appGroups: [AppGroup], associatedWith app: any SimulatorApp) -> [AppGroup] {
        appGroups.filter { $0.belongs(to: app) }
    }
}
