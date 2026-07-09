//
//  SimulatorApp.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 17.10.23.
//

import Foundation

protocol SimulatorApp: Identifiable, Sendable {
    var displayName: String { get }
    var bundleIdentifier: String { get }
    var appDocumentsFolderURL: URL? { get }
    var appPackageURL: URL? { get }
    var iconName: String { get }
    var hasUserDefaults: Bool { get }
    /// Most recent modification date of the app's bundle or data container.
    /// Used to detect whether an app actually changed between two discovery runs.
    var contentModifiedAt: Date? { get }
}

extension SimulatorApp {
    var id: String {
        bundleIdentifier
    }

    var contentModifiedAt: Date? {
        nil
    }
}

final class SimulatoriOSApp: SimulatorApp {
    let displayName: String
    let bundleIdentifier: String
    let appDocumentsFolderURL: URL?
    let appPackageURL: URL?
    let hasUserDefaults: Bool
    let contentModifiedAt: Date?
    let iconName = "iphone.gen3"

    let hasWatchApp: Bool

    init(
        displayName: String,
        bundleIdentifier: String,
        appDocumentsFolderURL: URL?,
        appPackageURL: URL?,
        hasWatchApp: Bool,
        hasUserDefaults: Bool,
        contentModifiedAt: Date? = nil
    ) {
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.appDocumentsFolderURL = appDocumentsFolderURL
        self.appPackageURL = appPackageURL
        self.hasWatchApp = hasWatchApp
        self.hasUserDefaults = hasUserDefaults
        self.contentModifiedAt = contentModifiedAt
    }
}

final class SimulatorWatchOSApp: SimulatorApp {
    let displayName: String
    let bundleIdentifier: String
    let appDocumentsFolderURL: URL?
    let hasUserDefaults: Bool
    let appPackageURL: URL?
    let contentModifiedAt: Date?
    let iconName = "applewatch"

    let companioniOSAppBundleIdentifier: String?

    init(
        displayName: String,
        bundleIdentifier: String,
        appDocumentsFolderURL: URL?,
        appPackageURL: URL?,
        hasUserDefaults: Bool,
        companioniOSAppBundleIdentifier: String?,
        contentModifiedAt: Date? = nil
    ) {
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.appDocumentsFolderURL = appDocumentsFolderURL
        self.appPackageURL = appPackageURL
        self.hasUserDefaults = hasUserDefaults
        self.companioniOSAppBundleIdentifier = companioniOSAppBundleIdentifier
        self.contentModifiedAt = contentModifiedAt
    }
}
