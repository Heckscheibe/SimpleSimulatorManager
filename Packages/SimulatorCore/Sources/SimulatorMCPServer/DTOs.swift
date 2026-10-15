//
//  DTOs.swift
//  SimulatorMCPServer
//

import Foundation
import SimulatorCore

// The shapes tools return to agents. Dates are ISO 8601, paths are absolute strings, and optional
// fields are left out rather than written as null — see ``JSONOutput``.

public struct DeviceDTO: Codable, Sendable, Equatable {
    public let udid: String
    public let name: String
    public let platform: String
    public let osVersion: String
    public let state: String
    public let lastBootedAt: Date?
    public let deviceFolder: String?

    public init(device: Device) {
        udid = device.udid
        name = device.name
        platform = device.simulatorPlatform.identifier
        osVersion = device.osVersion
        state = device.state.identifier
        lastBootedAt = device.lastBootedAt
        deviceFolder = device.url?.path
    }
}

public struct AppDTO: Codable, Sendable, Equatable {
    public let bundleIdentifier: String
    public let name: String
    /// `iOS` or `watchOS`.
    public let kind: String
    public let contentModifiedAt: Date?
    /// The domains the menu offers for "Copy UserDefaults as JSON", in the same order.
    public let userDefaultsDomains: [String]
    /// Whether an iOS app embeds a watch app; always false for a watch app itself.
    public let hasWatchApp: Bool
    public let companionBundleIdentifier: String?

    public init(app: any SimulatorApp) {
        bundleIdentifier = app.bundleIdentifier
        name = app.displayName
        contentModifiedAt = app.contentModifiedAt
        userDefaultsDomains = app.exportableUserDefaultsDomains

        switch app {
        case let watchApp as SimulatorWatchOSApp:
            kind = "watchOS"
            hasWatchApp = false
            companionBundleIdentifier = watchApp.companioniOSAppBundleIdentifier
        case let iOSApp as SimulatoriOSApp:
            kind = "iOS"
            hasWatchApp = iOSApp.hasWatchApp
            companionBundleIdentifier = nil
        default:
            kind = "iOS"
            hasWatchApp = false
            companionBundleIdentifier = nil
        }
    }
}

/// An app as found on one particular device.
public struct AppInstallationDTO: Codable, Sendable, Equatable {
    public let device: DeviceDTO
    public let app: AppDTO
}

public struct AppGroupDTO: Codable, Sendable, Equatable {
    public let identifier: String
    public let name: String
    public let groupFolder: String?
    /// Only present once something wrote preferences into the group, like the menu item.
    public let preferencesFolder: String?
    public let userDefaultsDomains: [String]

    public init(appGroup: AppGroup) {
        identifier = appGroup.identifier
        name = appGroup.name
        groupFolder = AppGroupShortcut.groupFolder.url(for: appGroup)?.path
        preferencesFolder = AppGroupShortcut.available(for: appGroup).contains(.userDefaults)
            ? AppGroupShortcut.userDefaults.url(for: appGroup)?.path
            : nil
        userDefaultsDomains = appGroup.exportableUserDefaultsDomains
    }
}

/// The folders the menu offers for an app, resolved the same way.
public struct AppContainersDTO: Codable, Sendable, Equatable {
    public let udid: String
    public let bundleIdentifier: String
    /// The app's data container (sandbox root, holding `Documents`, `Library` and `tmp`) — the
    /// menu's "Documents Folder".
    public let dataContainer: String?
    /// The folder holding the `.app` bundle — the menu's "App Package".
    public let bundleContainer: String?
    /// The `.app` bundle itself.
    public let appBundle: String?
    /// `Library/Preferences` inside the data container; only present once the app wrote preferences.
    public let preferencesFolder: String?
    public let appGroups: [AppGroupDTO]

    public init(udid: String, app: any SimulatorApp, appGroups: [AppGroup]) {
        self.udid = udid
        bundleIdentifier = app.bundleIdentifier
        dataContainer = AppContainerShortcut.documents.url(for: app)?.path
        bundleContainer = AppContainerShortcut.appPackage.url(for: app)?.path
        appBundle = app.appPackageURL?.path
        preferencesFolder = AppContainerShortcut.available(for: app).contains(.userDefaults)
            ? AppContainerShortcut.userDefaults.url(for: app)?.path
            : nil
        self.appGroups = appGroups.map(AppGroupDTO.init(appGroup:))
    }
}

public struct RecentAppDTO: Codable, Sendable, Equatable {
    public let udid: String
    public let deviceName: String
    public let deviceOSVersion: String
    /// When the app was last installed or updated: the newer of its bundle and data container.
    public let changedAt: Date
    public let app: AppDTO

    public init(appChange: AppChange) {
        udid = appChange.device.udid
        deviceName = appChange.device.name
        deviceOSVersion = appChange.device.osVersion
        changedAt = appChange.timestamp
        app = AppDTO(app: appChange.app)
    }
}

public struct CleanupCandidateDTO: Codable, Sendable, Equatable {
    /// Pass this to `delete_cleanup_candidate`.
    public let id: String
    public let name: String
    public let udid: String?
    public let platform: String?
    public let osVersion: String?
    public let lastBootedAt: Date?
    public let diskUsageBytes: Int64?
    public let reasons: [String]
    public let reasonSummary: String
    public let detailMessage: String?
    /// `simctlDelete` or `trashDirectory`.
    public let deletionMethod: String
    /// The folder that is moved to the Trash, for `trashDirectory` candidates.
    public let directory: String?

    public init(candidate: SimulatorCleanupCandidate) {
        id = candidate.id
        name = candidate.name
        udid = candidate.udid
        platform = candidate.simulatorPlatform?.identifier
        osVersion = candidate.osVersion
        lastBootedAt = candidate.lastBootedAt
        diskUsageBytes = candidate.diskUsageBytes
        reasons = candidate.reasons.map(\.rawValue)
        reasonSummary = candidate.reasonSummary
        detailMessage = candidate.detailMessage

        switch candidate.deletionMethod {
        case .simctlDelete:
            deletionMethod = "simctlDelete"
            directory = nil
        case let .trashDirectory(url):
            deletionMethod = "trashDirectory"
            directory = url.path
        }
    }
}

// MARK: - Stable identifiers

extension SimulatorPlatform {
    /// The value tools return and `list_devices(platform:)` filters on.
    public var identifier: String {
        switch self {
        case .iPhone:
            "iPhone"
        case .iPad:
            "iPad"
        case .watch:
            "watch"
        case .appleTV:
            "appleTV"
        case .visionPro:
            "visionPro"
        case .iPodTouch:
            "iPodTouch"
        }
    }

    static let allIdentifiers = ["iPhone", "iPad", "watch", "appleTV", "visionPro", "iPodTouch"]
}

extension DeviceState {
    /// The value tools return and `list_devices(state:)` filters on.
    public var identifier: String {
        switch self {
        case .off:
            "off"
        case .running:
            "running"
        }
    }

    static let allIdentifiers = ["off", "running"]
}
