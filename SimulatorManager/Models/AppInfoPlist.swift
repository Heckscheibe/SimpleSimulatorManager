//
//  AppInfoPlist.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 18.10.23.
//

import Foundation

enum Platform: String, Decodable {
    case iphonesimulator
    case watchsimulator
}

struct AppInfoPlist: DecodableURLContainer {
    static let infoPlistFileName = "Info.plist"
    
    enum CodingKeys: String, CodingKey {
        case cfBundleDisplayName = "CFBundleDisplayName"
        case cfBundleIdentifier = "CFBundleIdentifier"
        case platform = "DTPlatformName"
        case wkCompanionAppBundleIdentifier = "WKCompanionAppBundleIdentifier"
    }
    
    var isWatchApp: Bool {
        platform == .watchsimulator
    }
    
    let cfBundleDisplayName: String
    let cfBundleIdentifier: String
    let platform: Platform
    let wkCompanionAppBundleIdentifier: String?
    
    // not decodable attributes
    var hasCompanionWatchApp = false
    var url: URL?
}
