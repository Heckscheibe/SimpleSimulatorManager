//
//  AppGroupPlist.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 17.10.23.
//

import Foundation

public struct AppGroupPlist: DecodableURLContainer, Sendable {
    enum CodingKeys: String, CodingKey {
        case identifier = "MCMMetadataIdentifier"
        case uuid = "MCMMetadataUUID"
    }
    
    public var name: String {
        guard let index = identifier.firstIndex(of: ".") else {
            return ""
        }

        return String(identifier.suffix(from: identifier.index(after: index)))
    }
    
    public let identifier: String
    public let uuid: String
    
    public var url: URL?
}
