//
//  SimulatorQueryService.swift
//  SimulatorMCPServer
//

import Foundation
import os
import SimulatorCore

/// Which container's preferences `read_user_defaults` exports.
public enum UserDefaultsSubject: Sendable, Equatable {
    case app(bundleIdentifier: String)
    case appGroup(identifier: String)
}

/// A request named something that does not exist. Tools report these as `isError`, never as an
/// empty success, so an agent can tell a typo from an empty simulator.
public enum SimulatorQueryError: LocalizedError, Equatable {
    case devicesDirectoryUnavailable
    case unknownDevice(udid: String)
    case unknownApp(bundleIdentifier: String, udid: String?)
    case unknownAppGroup(identifier: String, udid: String)
    case unknownUserDefaultsDomain(domain: String, available: [String])
    case noUserDefaults(subject: String)
    case unknownCleanupCandidate(id: String)

    public var errorDescription: String? {
        switch self {
        case .devicesDirectoryUnavailable:
            "The CoreSimulator devices directory could not be located."
        case let .unknownDevice(udid):
            "No simulator with UDID \(udid) exists. Call list_devices for valid UDIDs."
        case let .unknownApp(bundleIdentifier, udid?):
            "No app with bundle identifier \(bundleIdentifier) is installed on simulator \(udid). Call list_apps for valid bundle identifiers."
        case let .unknownApp(bundleIdentifier, nil):
            "No app with bundle identifier \(bundleIdentifier) is installed on any simulator."
        case let .unknownAppGroup(identifier, udid):
            "No app group \(identifier) exists on simulator \(udid). Call list_app_groups for valid identifiers."
        case let .unknownUserDefaultsDomain(domain, available):
            "No UserDefaults domain \(domain) exists in this container. Available domains: \(available.joined(separator: ", "))."
        case let .noUserDefaults(subject):
            "\(subject) has not written any UserDefaults yet."
        case let .unknownCleanupCandidate(id):
            "No cleanup candidate with id \(id) exists. Call list_cleanup_candidates for current ids."
        }
    }
}

/// Everything the tools need, as one async façade. A protocol so the tool layer can be tested
/// without simulators on disk.
public protocol SimulatorQuerying: Sendable {
    func devices() async throws -> [DeviceDTO]
    func apps(onDeviceWithUdid udid: String) async throws -> [AppDTO]
    func installations(ofBundleIdentifier bundleIdentifier: String) async throws -> [AppInstallationDTO]
    func containers(ofBundleIdentifier bundleIdentifier: String, onDeviceWithUdid udid: String) async throws -> AppContainersDTO
    func appGroups(onDeviceWithUdid udid: String) async throws -> [AppGroupDTO]
    func recentApps(limit: Int) async throws -> [RecentAppDTO]
    func cleanupCandidates() async throws -> [CleanupCandidateDTO]
    func userDefaultsJSON(of subject: UserDefaultsSubject, onDeviceWithUdid udid: String, domain: String?) async throws -> String
    func shutDownAllSimulators() async throws
    func eraseDevice(withUdid udid: String) async throws
    func eraseAllSimulators() async throws
    func deleteCleanupCandidate(withId id: String) async throws -> CleanupCandidateDTO
}

/// Answers tool calls from the same services the menu bar app uses, so both always agree.
///
/// It loads from disk on every call instead of keeping state: the server is short-lived, the
/// simulators change underneath it, and `DeviceManager`'s publishers belong to the app.
public struct SimulatorQueryService: SimulatorQuerying {
    private let deviceLoader: DeviceLoader
    private let appDiscoveryService: AppDiscoveryService
    private let userDefaultsExporter: any UserDefaultsExporting
    private let resetService: any SimulatorResetServing
    private let cleanupService: any SimulatorCleanupServing

    /// Disk scans block for as long as the simulators take to enumerate, so — as in
    /// `SimulatorCleanupService.workQueue` — they run here rather than on a cooperative thread.
    private static let workQueue = DispatchQueue(
        label: "SimulatorQueryService.workQueue",
        qos: .userInitiated,
        attributes: .concurrent
    )

    public init(
        deviceLoader: DeviceLoader = DeviceLoader(),
        appDiscoveryService: AppDiscoveryService = AppDiscoveryService(),
        userDefaultsExporter: any UserDefaultsExporting = UserDefaultsExportService(),
        resetService: any SimulatorResetServing = SimulatorResetService(),
        cleanupService: any SimulatorCleanupServing = SimulatorCleanupService()
    ) {
        self.deviceLoader = deviceLoader
        self.appDiscoveryService = appDiscoveryService
        self.userDefaultsExporter = userDefaultsExporter
        self.resetService = resetService
        self.cleanupService = cleanupService
    }

    // MARK: - Reading

    public func devices() async throws -> [DeviceDTO] {
        try await onWorkQueue { [deviceLoader] in
            try Self.deviceList(from: deviceLoader)
                .sorted { ($0.name, $0.osVersion, $0.udid) < ($1.name, $1.osVersion, $1.udid) }
                .map(DeviceDTO.init(device:))
        }
    }

    public func apps(onDeviceWithUdid udid: String) async throws -> [AppDTO] {
        try await onWorkQueue { [self] in
            try loadDevice(withUdid: udid)
                .apps
                .sorted(by: Self.appOrder)
                .map(AppDTO.init(app:))
        }
    }

    public func installations(ofBundleIdentifier bundleIdentifier: String) async throws -> [AppInstallationDTO] {
        try await onWorkQueue { [self] in
            let installations = try loadAllDevicesWithoutAppGroups()
                .devices
                .sorted { ($0.name, $0.udid) < ($1.name, $1.udid) }
                .flatMap { device in
                    device.apps
                        .filter { $0.bundleIdentifier == bundleIdentifier }
                        .map { AppInstallationDTO(device: DeviceDTO(device: device), app: AppDTO(app: $0)) }
                }

            guard !installations.isEmpty else {
                throw SimulatorQueryError.unknownApp(bundleIdentifier: bundleIdentifier, udid: nil)
            }

            return installations
        }
    }

    public func containers(ofBundleIdentifier bundleIdentifier: String, onDeviceWithUdid udid: String) async throws -> AppContainersDTO {
        try await onWorkQueue { [self] in
            let device = try loadDevice(withUdid: udid)
            let app = try Self.app(withBundleIdentifier: bundleIdentifier, on: device)
            let appGroups = device.appGroups
                .filter { Self.appGroup($0, belongsTo: app) }
                .sorted { $0.identifier < $1.identifier }

            return AppContainersDTO(udid: device.udid, app: app, appGroups: appGroups)
        }
    }

    public func appGroups(onDeviceWithUdid udid: String) async throws -> [AppGroupDTO] {
        try await onWorkQueue { [self] in
            try loadDevice(withUdid: udid)
                .appGroups
                .sorted { $0.identifier < $1.identifier }
                .map(AppGroupDTO.init(appGroup:))
        }
    }

    public func recentApps(limit: Int) async throws -> [RecentAppDTO] {
        try await onWorkQueue { [self] in
            // The menu's list first, then its head, so a limit never reorders or re-dedupes it.
            try RecentApps.initial(from: loadAllDevicesWithoutAppGroups().initialAppChanges)
                .prefix(limit)
                .map(RecentAppDTO.init(appChange:))
        }
    }

    public func cleanupCandidates() async throws -> [CleanupCandidateDTO] {
        try await cleanupService.loadCleanupCandidates().map(CleanupCandidateDTO.init(candidate:))
    }

    public func userDefaultsJSON(of subject: UserDefaultsSubject, onDeviceWithUdid udid: String, domain: String?) async throws -> String {
        try await onWorkQueue { [self] in
            let device = try loadDevice(withUdid: udid)

            // `ownDomain` is the bundle / group identifier, exactly as `ContainerShortcutHandling` passes it.
            let preferencesURL: URL?
            let ownDomain: String
            let domains: [String]
            let subjectName: String

            switch subject {
            case let .app(bundleIdentifier):
                let app = try Self.app(withBundleIdentifier: bundleIdentifier, on: device)
                preferencesURL = AppContainerShortcut.userDefaults.url(for: app)
                ownDomain = app.bundleIdentifier
                domains = app.userDefaultsDomains
                subjectName = "App \(bundleIdentifier)"
            case let .appGroup(identifier):
                guard let appGroup = device.appGroups.first(where: { $0.identifier == identifier }) else {
                    throw SimulatorQueryError.unknownAppGroup(identifier: identifier, udid: udid)
                }

                preferencesURL = AppGroupShortcut.userDefaults.url(for: appGroup)
                ownDomain = appGroup.identifier
                domains = appGroup.userDefaultsDomains
                subjectName = "App group \(identifier)"
            }

            guard let preferencesURL, !domains.isEmpty else {
                throw SimulatorQueryError.noUserDefaults(subject: subjectName)
            }

            if let domain, !domains.contains(domain) {
                throw SimulatorQueryError.unknownUserDefaultsDomain(domain: domain, available: domains)
            }

            return try userDefaultsExporter.exportJSON(fromPreferencesDirectoryAt: preferencesURL,
                                                       ownDomain: ownDomain,
                                                       domain: domain)
        }
    }

    // MARK: - Acting

    public func shutDownAllSimulators() async throws {
        try await resetService.shutDownAllSimulators()
    }

    public func eraseDevice(withUdid udid: String) async throws {
        // Validated against the device list first, so simctl never sees an arbitrary string.
        let knownUdids = try await onWorkQueue { [deviceLoader] in
            try Self.deviceList(from: deviceLoader).map(\.udid)
        }

        guard knownUdids.contains(udid) else {
            throw SimulatorQueryError.unknownDevice(udid: udid)
        }

        try await resetService.shutDownAndEraseSimulator(deviceUdid: udid)
    }

    public func eraseAllSimulators() async throws {
        try await resetService.shutDownAndResetAllSimulators()
    }

    public func deleteCleanupCandidate(withId id: String) async throws -> CleanupCandidateDTO {
        // Reloaded rather than trusted from an earlier listing: only a candidate that still
        // qualifies right now is deleted, and the caller never supplies a path.
        guard let candidate = try await cleanupService.loadCleanupCandidates().first(where: { $0.id == id }) else {
            throw SimulatorQueryError.unknownCleanupCandidate(id: id)
        }

        try await cleanupService.deleteCleanupCandidate(candidate)
        os_log("MCP server deleted cleanup candidate %{public}@", id)

        return CleanupCandidateDTO(candidate: candidate)
    }
}

// MARK: - Helpers

private extension SimulatorQueryService {
    static func appOrder(_ lhs: any SimulatorApp, _ rhs: any SimulatorApp) -> Bool {
        (lhs.displayName.localizedLowercase, lhs.bundleIdentifier) < (rhs.displayName.localizedLowercase, rhs.bundleIdentifier)
    }

    static func deviceList(from deviceLoader: DeviceLoader) throws -> [Device] {
        guard deviceLoader.devicesDirectoryURL != nil else {
            throw SimulatorQueryError.devicesDirectoryUnavailable
        }

        return deviceLoader.loadDeviceList()
    }

    static func app(withBundleIdentifier bundleIdentifier: String, on device: Device) throws -> any SimulatorApp {
        guard let app = device.apps.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            throw SimulatorQueryError.unknownApp(bundleIdentifier: bundleIdentifier, udid: device.udid)
        }

        return app
    }

    /// An app group belongs to an app whose bundle identifier is the group's name or starts with
    /// it as a whole dot-separated prefix — so `group.com.example.notes` belongs to
    /// `com.example.notes` and `com.example.notes.widget`, but not to `com.example.notesplus`.
    static func appGroup(_ appGroup: AppGroup, belongsTo app: any SimulatorApp) -> Bool {
        let name = appGroup.name

        return !name.isEmpty && (app.bundleIdentifier == name || app.bundleIdentifier.hasPrefix(name + "."))
    }

    /// Every device with its apps. App groups are skipped: no caller of this needs them.
    func loadAllDevicesWithoutAppGroups() throws -> DeviceLoader.LoadedDevices {
        guard let loadedDevices = deviceLoader.loadDevices(includingAppGroups: false) else {
            throw SimulatorQueryError.devicesDirectoryUnavailable
        }

        return loadedDevices
    }

    /// Loads the device whose folder is named `udid`. The UDID must be a single path component and
    /// the folder's `device.plist` must carry the same UDID, so a value such as `../..` can never
    /// resolve to a folder outside the devices directory — without decoding every other device.
    func loadDevice(withUdid udid: String) throws -> Device {
        guard deviceLoader.devicesDirectoryURL != nil else {
            throw SimulatorQueryError.devicesDirectoryUnavailable
        }
        guard Self.isSinglePathComponent(udid),
              let device = deviceLoader.loadDevice(withUdid: udid),
              device.udid == udid else {
            throw SimulatorQueryError.unknownDevice(udid: udid)
        }

        return device
    }

    static func isSinglePathComponent(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/")
    }

    func onWorkQueue<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            Self.workQueue.async {
                continuation.resume(with: Result { try work() })
            }
        }
    }
}
