//
//  AppGroup.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 17.10.23.
//

import Foundation

class AppGroup: DecodableURLContainer {
    static let appGroupsPath = "data/Containers/Shared/AppGroup"
    
    enum CodingKeys: String, CodingKey {
        case identifier = "MCMMetadataIdentifier"
        case uuid = "MCMMetadataUUID"
    }
    
    var name: String {
        guard let index = identifier.firstIndex(of: ".") else {
            return ""
        }
        return String(identifier.suffix(from: identifier.index(after: index)))
    }
    
    let identifier: String
    let uuid: String
    
    var url: URL?
}

extension AppGroup: Identifiable {
    var id: String {
        identifier
    }
}
