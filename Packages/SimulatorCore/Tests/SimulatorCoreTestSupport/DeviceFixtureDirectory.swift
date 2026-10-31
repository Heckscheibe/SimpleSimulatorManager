import Foundation
import SimulatorCore

/// A throwaway CoreSimulator `Devices` directory holding hand-written plist fixtures, laid out the
/// way CoreSimulator writes it, so loading can be exercised against known devices, apps, app groups
/// and UserDefaults instead of the machine's own simulators.
///
/// Shared by every test target in this package, and compiled into the app's test target as well,
/// so there is one fixture writer for both.
public struct DeviceFixtureDirectory {
    public enum DeviceTypeIdentifier {
        public static let iPhone = "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro"
        public static let iPad = "com.apple.CoreSimulator.SimDeviceType.iPad-Air-11-inch-M3"
        public static let watch = "com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-10-46mm"
    }

    /// Paths of an installed app, for asserting what loading reports.
    public struct InstalledApp {
        public let dataContainerURL: URL
        public let bundleURL: URL
    }

    public let url: URL

    public init() throws {
        let temporaryURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("simulator-core-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryURL, withIntermediateDirectories: true)

        // Directory enumeration reports `/private/var/…` for the temporary directory's `/var/…`, so
        // the fixture uses the real path for its expectations to compare equal to loaded paths.
        // `resolvingSymlinksInPath()` would strip `/private` again, hence `realpath`.
        guard let realPath = realpath(temporaryURL.path, nil) else {
            throw CocoaError(.fileNoSuchFile)
        }

        defer { free(realPath) }
        url = URL(fileURLWithPath: String(cString: realPath), isDirectory: true)
    }

    public func remove() {
        try? FileManager.default.removeItem(at: url)
    }

    public func removeDevice(udid: String) {
        try? FileManager.default.removeItem(at: deviceURL(udid: udid))
    }

    public func deviceURL(udid: String) -> URL {
        url.appendingPathComponent(udid, isDirectory: true)
    }

    /// Writes the same keys a real `device.plist` carries, including the uppercase `UDID`.
    public func writeDevice(
        udid: String,
        name: String,
        deviceTypeIdentifier: String = DeviceTypeIdentifier.iPhone,
        runtime: String = "com.apple.CoreSimulator.SimRuntime.iOS-26-1",
        state: DeviceState = .off,
        lastBootedAt: Date? = nil
    ) throws {
        var plist: [String: Any] = [
            "UDID": udid,
            "name": name,
            "runtime": runtime,
            "deviceType": deviceTypeIdentifier,
            "state": state.rawValue
        ]
        plist["lastBootedAt"] = lastBootedAt
        try write(plist, to: deviceURL(udid: udid).appendingPathComponent(SimulatorPaths.devicePlistName))
    }

    /// A device folder whose `device.plist` is missing entirely.
    public func writeDeviceFolderWithoutPlist(udid: String) throws {
        try FileManager.default.createDirectory(at: deviceURL(udid: udid), withIntermediateDirectories: true)
    }

    /// A device folder whose `device.plist` is not a property list.
    public func writeDeviceWithUnreadablePlist(udid: String) throws {
        let folder = deviceURL(udid: udid)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not a plist".utf8).write(to: folder.appendingPathComponent(SimulatorPaths.devicePlistName))
    }

    /// Installs an iOS app: an `.app` bundle under `Containers/Bundle/Application` and a data
    /// container under `Containers/Data/Application`, tied together by the metadata identifier.
    /// Every entry of `userDefaults` becomes `Library/Preferences/<domain>.plist`.
    @discardableResult
    public func writeApp(
        bundleIdentifier: String,
        name: String,
        onDeviceWithUdid udid: String,
        userDefaults: [String: [String: Any]] = [:],
        modifiedAt: Date? = nil,
        bundleModifiedAt: Date? = nil,
        containerModifiedAt: Date? = nil,
        additionalInfoPlistEntries: [String: Any] = [:]
    ) throws -> InstalledApp {
        let dataFolder = deviceURL(udid: udid).appendingPathComponent(SimulatorPaths.dataFolderName)

        let bundleURL = dataFolder
            .appendingPathComponent(SimulatorPaths.appBundleApplicationsPath)
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("\(name).app")
        try write([
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleName": name,
            "DTPlatformName": "iphonesimulator"
        ].merging(additionalInfoPlistEntries) { _, additional in additional }, to: bundleURL.appendingPathComponent(Self.infoPlistFileName))

        let containerURL = dataFolder
            .appendingPathComponent(SimulatorPaths.appDataApplicationsPath)
            .appendingPathComponent(UUID().uuidString)
        try write(["MCMMetadataIdentifier": bundleIdentifier], to: containerURL.appendingPathComponent(Self.metadataFileName))
        try writePreferences(userDefaults, inContainerAt: containerURL)

        // `modifiedAt` sets both; the specific dates win, so a test can model an app that has been
        // running (container touched) without having been reinstalled (bundle untouched).
        if let containerDate = containerModifiedAt ?? modifiedAt {
            try setModificationDate(containerDate, of: containerURL)
        }
        if let bundleDate = bundleModifiedAt ?? modifiedAt {
            try setModificationDate(bundleDate, of: bundleURL)
        }

        return InstalledApp(dataContainerURL: containerURL, bundleURL: bundleURL)
    }

    /// Writes an app group's shared container. Discovery only keeps a group that belongs to an
    /// installed app: its name (the identifier after `group.`) is the app's bundle identifier or a
    /// dot-separated prefix of it.
    @discardableResult
    public func writeAppGroup(
        identifier: String,
        onDeviceWithUdid udid: String,
        userDefaults: [String: [String: Any]] = [:]
    ) throws -> URL {
        let uuid = UUID().uuidString
        let groupURL = deviceURL(udid: udid)
            .appendingPathComponent(SimulatorPaths.appGroupsPath)
            .appendingPathComponent(uuid)
        try write(["MCMMetadataIdentifier": identifier, "MCMMetadataUUID": uuid],
                  to: groupURL.appendingPathComponent(Self.metadataFileName))
        try writePreferences(userDefaults, inContainerAt: groupURL)

        return groupURL
    }

    public func writeDSStore() throws {
        try Data().write(to: url.appendingPathComponent(".DS_Store"))
    }

    // The same names CoreSimulator uses; spelled out because SimulatorCore keeps its own internal.
    private static let infoPlistFileName = "Info.plist"
    private static let metadataFileName = ".com.apple.mobile_container_manager.metadata.plist"

    private func writePreferences(_ userDefaults: [String: [String: Any]], inContainerAt containerURL: URL) throws {
        for (domain, values) in userDefaults {
            try write(values, to: containerURL
                .appendingPathComponent(SimulatorPaths.userDefaultsPath)
                .appendingPathComponent("\(domain).plist"))
        }
    }

    private func setModificationDate(_ date: Date, of url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    private func write(_ plist: [String: Any], to fileURL: URL) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: fileURL)
    }
}
