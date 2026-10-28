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
    /// Whether this is an XCUITest runner Xcode generated, rather than an app anyone built to be
    /// used. Discovery only flags it; hiding it is each consumer's decision. See ``TestRunnerApp``.
    var isTestRunner: Bool { get }
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

    /// Identifies one *install*, where ``bundleIdentifier`` identifies only an app.
    ///
    /// A simulator can hold two containers sharing a bundle identifier — a stale install alongside
    /// a fresh one — which `DeviceAppMonitoringService.computeAppChanges` documents and guards
    /// against. The container directory is the only thing that separates them, and it is stable
    /// across reloads, so identity built on it survives a device refresh.
    public var installIdentifier: String {
        guard let containerIdentifier = appPackageURL?.deletingLastPathComponent().lastPathComponent,
              !containerIdentifier.isEmpty else {
            return bundleIdentifier
        }

        return "\(bundleIdentifier)-\(containerIdentifier)"
    }

    public var contentModifiedAt: Date? {
        nil
    }

    public var isTestRunner: Bool {
        false
    }
}

/// How an app is recognised as a generated UI test runner.
///
/// Deliberately not detected from a `PlugIns/*.xctest` bundle (an ordinary app that hosts its own
/// unit tests embeds those) or from a display name containing `Runner` (every Flutter iOS target
/// is called `Runner`).
enum TestRunnerApp {
    /// Xcode 11 and later append this to the test target's identifier; the developer cannot choose it.
    static let identifierSuffix = ".xctrunner"
    /// Xcode 10 and earlier named runners `com.apple.test.<Target>-Runner`.
    static let legacyIdentifierPrefix = "com.apple.test."
    static let legacyIdentifierSuffix = "-Runner"
    /// Private Apple class that only the generated runner template names as its scene delegate.
    static let sceneDelegateClassName = "_XCTRunnerAppDelegate"

    /// Any one rule matching is sufficient.
    static func isRunner(bundleIdentifier: String, sceneDelegateClassName: String?) -> Bool {
        bundleIdentifier.hasSuffix(identifierSuffix)
            || (bundleIdentifier.hasPrefix(legacyIdentifierPrefix) && bundleIdentifier.hasSuffix(legacyIdentifierSuffix))
            || sceneDelegateClassName == Self.sceneDelegateClassName
    }
}

public final class SimulatoriOSApp: SimulatorApp {
    public let displayName: String
    public let bundleIdentifier: String
    public let appDocumentsFolderURL: URL?
    public let appPackageURL: URL?
    public let userDefaultsDomains: [String]
    public let contentModifiedAt: Date?
    public let isTestRunner: Bool
    public let iconName = "iphone.gen3"

    public let hasWatchApp: Bool

    public init(
        displayName: String,
        bundleIdentifier: String,
        appDocumentsFolderURL: URL?,
        appPackageURL: URL?,
        hasWatchApp: Bool,
        userDefaultsDomains: [String],
        contentModifiedAt: Date? = nil,
        isTestRunner: Bool = false
    ) {
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.appDocumentsFolderURL = appDocumentsFolderURL
        self.appPackageURL = appPackageURL
        self.hasWatchApp = hasWatchApp
        self.userDefaultsDomains = userDefaultsDomains
        self.contentModifiedAt = contentModifiedAt
        self.isTestRunner = isTestRunner
    }
}

public final class SimulatorWatchOSApp: SimulatorApp {
    public let displayName: String
    public let bundleIdentifier: String
    public let appDocumentsFolderURL: URL?
    public let userDefaultsDomains: [String]
    public let appPackageURL: URL?
    public let contentModifiedAt: Date?
    public let isTestRunner: Bool
    public let iconName = "applewatch"

    public let companioniOSAppBundleIdentifier: String?

    public init(
        displayName: String,
        bundleIdentifier: String,
        appDocumentsFolderURL: URL?,
        appPackageURL: URL?,
        userDefaultsDomains: [String],
        companioniOSAppBundleIdentifier: String?,
        contentModifiedAt: Date? = nil,
        isTestRunner: Bool = false
    ) {
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.appDocumentsFolderURL = appDocumentsFolderURL
        self.appPackageURL = appPackageURL
        self.userDefaultsDomains = userDefaultsDomains
        self.companioniOSAppBundleIdentifier = companioniOSAppBundleIdentifier
        self.contentModifiedAt = contentModifiedAt
        self.isTestRunner = isTestRunner
    }
}
