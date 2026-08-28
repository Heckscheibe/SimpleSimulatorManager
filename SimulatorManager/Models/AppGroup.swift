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
