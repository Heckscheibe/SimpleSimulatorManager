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
    let hasUserDefaults: Bool

    var url: URL?
    
    init(identifier: String,
         uuid: String,
         hasUserDefaults: Bool,
         url: URL? = nil) {
        self.identifier = identifier
        self.uuid = uuid
        self.hasUserDefaults = hasUserDefaults
        self.url = url
    }
}

extension AppGroup: Identifiable {
    var id: String {
        identifier
    }
}
