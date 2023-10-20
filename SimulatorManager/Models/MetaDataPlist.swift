//
//  MetaDataPlist.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 18.10.23.
//

import Foundation

struct MetaDataPlist: DecodableURLContainer {
    static let fileName = ".com.apple.mobile_container_manager.metadata.plist"
    
    enum CodingKeys: String, CodingKey {
        case mcmMetadataIdentifier = "MCMMetadataIdentifier"
    }
    
    let mcmMetadataIdentifier: String
    var url: URL?
}
