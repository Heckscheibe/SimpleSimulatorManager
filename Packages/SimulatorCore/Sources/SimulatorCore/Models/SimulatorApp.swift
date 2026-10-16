//
//  SimulatorApp.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 17.10.23.
//

import Foundation

public protocol SimulatorApp: Identifiable, Sendable {
    var displayName: String { get }
    var bundleIdentifier: String { get }
    var appDocumentsFolderURL: URL? { get }
    var appPackageURL: URL? { get }
    var iconName: String { get }
    /// Every defaults domain found in the app's container, suites included. See ``UserDefaultsDomain``.
    var userDefaultsDomains: [String] { get }
    /// Most recent modification date of the app's bundle or data container.
    /// Used to detect whether an app actually changed between two discovery runs.
    var contentModifiedAt: Date? { get }
}

extension SimulatorApp {
    public var id: String {
        bundleIdentifier
    }

    public var hasUserDefaults: Bool {
        !userDefaultsDomains.isEmpty
    }

    /// The domains the menu offers and the export writes, in the order they are listed.
    public var exportableUserDefaultsDomains: [String] {
        UserDefaultsDomain.appDomains(in: userDefaultsDomains, ownDomain: bundleIdentifier)
    }

    public var contentModifiedAt: Date? {
        nil
    }
}

public final class SimulatoriOSApp: SimulatorApp {
    public let displayName: String
    public let bundleIdentifier: String
    public let appDocumentsFolderURL: URL?
    public let appPackageURL: URL?
    public let userDefaultsDomains: [String]
    public let contentModifiedAt: Date?
    public let iconName = "iphone.gen3"

    public let hasWatchApp: Bool

    public init(
        displayName: String,
        bundleIdentifier: String,
        appDocumentsFolderURL: URL?,
        appPackageURL: URL?,
        hasWatchApp: Bool,
        userDefaultsDomains: [String],
        contentModifiedAt: Date? = nil
    ) {
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.appDocumentsFolderURL = appDocumentsFolderURL
        self.appPackageURL = appPackageURL
        self.hasWatchApp = hasWatchApp
        self.userDefaultsDomains = userDefaultsDomains
        self.contentModifiedAt = contentModifiedAt
    }
}

public final class SimulatorWatchOSApp: SimulatorApp {
    public let displayName: String
    public let bundleIdentifier: String
    public let appDocumentsFolderURL: URL?
    public let userDefaultsDomains: [String]
    public let appPackageURL: URL?
    public let contentModifiedAt: Date?
    public let iconName = "applewatch"

    public let companioniOSAppBundleIdentifier: String?

    public init(
        displayName: String,
        bundleIdentifier: String,
        appDocumentsFolderURL: URL?,
        appPackageURL: URL?,
        userDefaultsDomains: [String],
        companioniOSAppBundleIdentifier: String?,
        contentModifiedAt: Date? = nil
    ) {
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.appDocumentsFolderURL = appDocumentsFolderURL
        self.appPackageURL = appPackageURL
        self.userDefaultsDomains = userDefaultsDomains
        self.companioniOSAppBundleIdentifier = companioniOSAppBundleIdentifier
        self.contentModifiedAt = contentModifiedAt
    }
}
