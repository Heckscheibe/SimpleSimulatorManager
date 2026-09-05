//
//  AppInfoPlist.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 18.10.23.
//

import Foundation

enum AppTargetPlatform: String, Decodable {
    case iphonesimulator
    case watchsimulator
}

struct AppInfoPlist: DecodableURLContainer {
    static let infoPlistFileName = "Info.plist"
    
    enum CodingKeys: String, CodingKey {
        case cfBundleDisplayName = "CFBundleDisplayName"
        case cfBundleName = "CFBundleName"
        case cfBundleIdentifier = "CFBundleIdentifier"
        case cfBundleShortVersionString = "CFBundleShortVersionString"
        case cfBundleVersion = "CFBundleVersion"
        case platform = "DTPlatformName"
        case wkCompanionAppBundleIdentifier = "WKCompanionAppBundleIdentifier"
    }
    
    var isWatchApp: Bool {
        platform == .watchsimulator
    }
    
    let cfBundleDisplayName: String?
    let cfBundleName: String
    let cfBundleIdentifier: String
    /// The marketing and build versions, as the bundle recorded them. Snapshots put both in their
    /// manifest so a restore can warn when the installed app is no longer the one captured.
    let cfBundleShortVersionString: String?
    let cfBundleVersion: String?
    let platform: AppTargetPlatform
    let wkCompanionAppBundleIdentifier: String?
    
    // not decoded attributes
    var hasCompanionWatchApp = false
    var url: URL?

    /// Decoded by hand only for the two version keys: both are strings by convention, but a build
    /// that wrote either as a number would fail the synthesised decode and drop the app from
    /// discovery entirely. A version this app cannot read is worth losing; the app is not.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        cfBundleDisplayName = try container.decodeIfPresent(String.self, forKey: .cfBundleDisplayName)
        cfBundleName = try container.decode(String.self, forKey: .cfBundleName)
        cfBundleIdentifier = try container.decode(String.self, forKey: .cfBundleIdentifier)
        platform = try container.decode(AppTargetPlatform.self, forKey: .platform)
        wkCompanionAppBundleIdentifier = try container.decodeIfPresent(String.self, forKey: .wkCompanionAppBundleIdentifier)
        cfBundleShortVersionString = Self.decodeVersion(from: container, forKey: .cfBundleShortVersionString)
        cfBundleVersion = Self.decodeVersion(from: container, forKey: .cfBundleVersion)
    }

    private static func decodeVersion(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> String? {
        if let string = try? container.decodeIfPresent(String.self, forKey: key) {
            return string
        }
        if let number = try? container.decodeIfPresent(Int.self, forKey: key) {
            return String(number)
        }
        if let number = try? container.decodeIfPresent(Double.self, forKey: key) {
            return String(number)
        }

        return nil
    }
}
