//
//  AppGroup.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 14.03.24.
//

import Foundation

class AppGroup {
    var name: String {
        guard let index = identifier.firstIndex(of: ".") else {
            return ""
        }

        return String(identifier.suffix(from: identifier.index(after: index)))
    }

    let identifier: String
    let uuid: String

    /// Every defaults domain found in the shared container, suites included.
    let userDefaultsDomains: [String]

    var hasUserDefaults: Bool {
        !userDefaultsDomains.isEmpty
    }

    var exportableUserDefaultsDomains: [String] {
        UserDefaultsDomain.appDomains(in: userDefaultsDomains, ownDomain: identifier)
    }

    var url: URL?
    
    init(
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
    var id: String {
        identifier
    }
}

extension AppGroup {
    /// Whether `app` shares this group's container.
    ///
    /// There is no record on either side that says so: the only available signal is that a group
    /// identifier is conventionally the app's bundle identifier with a `group.` prefix, so the
    /// group's ``name`` appears inside the bundle identifier. Discovery has always used this rule
    /// to decide which groups belong to a device's apps; snapshots need the same answer per app,
    /// and the two must not drift apart, so it lives here rather than in either caller.
    func isAssociated(with app: any SimulatorApp) -> Bool {
        !name.isEmpty && app.bundleIdentifier.contains(name)
    }

    static func groups(in appGroups: [AppGroup], associatedWith app: any SimulatorApp) -> [AppGroup] {
        appGroups.filter { $0.isAssociated(with: app) }
    }
}
