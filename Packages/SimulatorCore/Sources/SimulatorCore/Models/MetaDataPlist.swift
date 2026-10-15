//
//  MetaDataPlist.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 18.10.23.
//

import Foundation

public struct MetaDataPlist: DecodableURLContainer, Sendable {
    public static let fileName = ".com.apple.mobile_container_manager.metadata.plist"
    
    enum CodingKeys: String, CodingKey {
        case mcmMetadataIdentifier = "MCMMetadataIdentifier"
    }
    
    public let mcmMetadataIdentifier: String
    public var url: URL?
}
