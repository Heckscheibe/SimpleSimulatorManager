//
//  AppGroup.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 17.10.23.
//

import Foundation

struct AppGroup: Decodable {
    static let appGroupsPath = "data/Containers/Shared/AppGroup"
    
    enum CodingKeys: String, CodingKey {
        case identifier = "MCMMetadataIdentifier"
        case uuid = "MCMMetadataUUID"
    }
    
    let identifier: String
    let uuid: String
}
