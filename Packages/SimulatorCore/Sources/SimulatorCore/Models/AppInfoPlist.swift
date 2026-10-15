//
//  AppInfoPlist.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 18.10.23.
//

import Foundation

public enum AppTargetPlatform: String, Decodable, Sendable {
    case iphonesimulator
    case watchsimulator
}

public struct AppInfoPlist: DecodableURLContainer, Sendable {
    public static let infoPlistFileName = "Info.plist"
    
    enum CodingKeys: String, CodingKey {
        case cfBundleDisplayName = "CFBundleDisplayName"
        case cfBundleName = "CFBundleName"
        case cfBundleIdentifier = "CFBundleIdentifier"
        case platform = "DTPlatformName"
        case wkCompanionAppBundleIdentifier = "WKCompanionAppBundleIdentifier"
    }
    
    public var isWatchApp: Bool {
        platform == .watchsimulator
    }
    
    public let cfBundleDisplayName: String?
    public let cfBundleName: String
    public let cfBundleIdentifier: String
    public let platform: AppTargetPlatform
    public let wkCompanionAppBundleIdentifier: String?
    
    // not decoded attributes
    public var hasCompanionWatchApp = false
    public var url: URL?
}
