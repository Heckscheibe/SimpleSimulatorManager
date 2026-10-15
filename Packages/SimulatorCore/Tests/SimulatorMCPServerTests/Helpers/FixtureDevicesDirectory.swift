import Foundation
import SimulatorCore

/// A throwaway CoreSimulator `Devices` directory laid out the way CoreSimulator writes it, so the
/// server can be exercised end to end without touching the machine's own simulators.
///
/// Extends the SimulatorCore test fixture with UserDefaults and app groups, which the tools expose.
struct FixtureDevicesDirectory {
    enum DeviceTypeIdentifier {
        static let iPhone = "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro"
        static let iPad = "com.apple.CoreSimulator.SimDeviceType.iPad-Air-11-inch-M3"
        static let watch = "com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-10-46mm"
    }

    /// Paths of an installed app, for asserting what the tools report.
    struct InstalledApp {
        let dataContainerURL: URL
        let bundleURL: URL
    }

    let url: URL

    init() throws {
        let temporaryURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("simulator-mcp-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryURL, withIntermediateDirectories: true)

        // Directory enumeration reports `/private/var/…` for the temporary directory's `/var/…`, so
        // the fixture uses the real path for its expectations to compare equal to what tools return.
        // `resolvingSymlinksInPath()` would strip `/private` again, hence `realpath`.
        guard let realPath = realpath(temporaryURL.path, nil) else {
            throw CocoaError(.fileNoSuchFile)
        }

        defer { free(realPath) }
        url = URL(fileURLWithPath: String(cString: realPath), isDirectory: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }

    func deviceURL(udid: String) -> URL {
        url.appendingPathComponent(udid, isDirectory: true)
    }

    /// Writes the same keys a real `device.plist` carries, including the uppercase `UDID`.
    func writeDevice(
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

    /// Installs an iOS app: an `.app` bundle under `Containers/Bundle/Application` and a data
    /// container under `Containers/Data/Application`, tied together by the metadata identifier.
    /// Every entry of `userDefaults` becomes `Library/Preferences/<domain>.plist`.
    @discardableResult
    func writeApp(
        bundleIdentifier: String,
        name: String,
        onDeviceWithUdid udid: String,
        userDefaults: [String: [String: Any]] = [:],
        modifiedAt: Date? = nil
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
        ], to: bundleURL.appendingPathComponent("Info.plist"))

        let containerURL = dataFolder
            .appendingPathComponent(SimulatorPaths.appDataApplicationsPath)
            .appendingPathComponent(UUID().uuidString)
        try write(["MCMMetadataIdentifier": bundleIdentifier], to: containerURL.appendingPathComponent(Self.metadataFileName))
        try writePreferences(userDefaults, inContainerAt: containerURL)

        if let modifiedAt {
            try setModificationDate(modifiedAt, of: containerURL)
            try setModificationDate(modifiedAt, of: bundleURL)
        }

        return InstalledApp(dataContainerURL: containerURL, bundleURL: bundleURL)
    }

    /// Writes an app group's shared container. Discovery only keeps a group whose name (the
    /// identifier after `group.`) is part of an installed app's bundle identifier.
    @discardableResult
    func writeAppGroup(
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
