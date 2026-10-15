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
