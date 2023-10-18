//
//  MetaDataPlist.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 18.10.23.
//

import Foundation

struct MetaDataPlist: Decodable {
    enum CodingKeys: String, CodingKey {
        case mcmMetadataIdentifier = "MCMMetadataIdentifier"
    }
    
    let mcmMetadataIdentifier: String
}
