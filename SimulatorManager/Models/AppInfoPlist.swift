//
//  AppInfoPlist.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 18.10.23.
//

import Foundation

struct AppInfoPlist: DecodableURLContainer {
    static let infoPlistFileName = "Info.plist"
    
    enum CodingKeys: String, CodingKey {
        case cfBundleDisplayName = "CFBundleDisplayName"
        case cfBundleIdentifier = "CFBundleIdentifier"
        case wkCompanionAppBundleIdentifier = "WKCompanionAppBundleIdentifier"
    }
    
    let cfBundleDisplayName: String
    let cfBundleIdentifier: String
    let wkCompanionAppBundleIdentifier: String?
    
    // not decodable attributes
    var hasWatchApp = false
    var url: URL?
}
