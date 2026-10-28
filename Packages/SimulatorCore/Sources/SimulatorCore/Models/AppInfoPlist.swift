//
//  AppInfoPlist.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 18.10.23.
//

import Foundation

enum AppTargetPlatform: String, Decodable, Sendable {
    case iphonesimulator
    case watchsimulator
}

struct AppInfoPlist: DecodableURLContainer, Sendable {
    static let infoPlistFileName = "Info.plist"
    
    enum CodingKeys: String, CodingKey {
        case cfBundleDisplayName = "CFBundleDisplayName"
        case cfBundleName = "CFBundleName"
        case cfBundleIdentifier = "CFBundleIdentifier"
        case platform = "DTPlatformName"
        case wkCompanionAppBundleIdentifier = "WKCompanionAppBundleIdentifier"
        case sceneManifest = "UIApplicationSceneManifest"
    }
    
    var isWatchApp: Bool {
        platform == .watchsimulator
    }
    
    let cfBundleDisplayName: String?
    let cfBundleName: String
    let cfBundleIdentifier: String
    let platform: AppTargetPlatform
    let wkCompanionAppBundleIdentifier: String?
    let sceneManifest: SceneManifest?

    var isTestRunner: Bool {
        TestRunnerApp.isRunner(bundleIdentifier: cfBundleIdentifier,
                               sceneDelegateClassName: sceneManifest?.delegateClassName)
    }
    
    // not decoded attributes
    var hasCompanionWatchApp = false
    var url: URL?
}

/// The one value of `UIApplicationSceneManifest` that is read: the application scene's delegate
/// class, three levels down.
///
/// Decoding never throws. A throw here would fail the whole `AppInfoPlist`, and
/// `AppDiscoveryService.loadAppInfoPlists` answers that by dropping the app from the list, so a
/// manifest of an unexpected shape would hide a real app. Most apps have no manifest at all.
struct SceneManifest: Decodable, Sendable {
    let delegateClassName: String?

    private enum CodingKeys: String, CodingKey {
        case configurations = "UISceneConfigurations"
    }

    private enum RoleKeys: String, CodingKey {
        case windowApplication = "UIWindowSceneSessionRoleApplication"
    }

    private struct Configuration: Decodable {
        let delegateClassName: String?

        private enum CodingKeys: String, CodingKey {
            case delegateClassName = "UISceneDelegateClassName"
        }

        init(from decoder: Decoder) {
            delegateClassName = try? decoder.container(keyedBy: CodingKeys.self)
                .decodeIfPresent(String.self, forKey: .delegateClassName)
        }
    }

    init(from decoder: Decoder) {
        let configurations = try? decoder.container(keyedBy: CodingKeys.self)
            .nestedContainer(keyedBy: RoleKeys.self, forKey: .configurations)
            .decodeIfPresent([Configuration].self, forKey: .windowApplication)

        delegateClassName = configurations?.compactMap(\.delegateClassName).first
    }
}
