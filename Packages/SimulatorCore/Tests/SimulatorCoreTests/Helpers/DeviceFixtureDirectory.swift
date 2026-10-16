import Foundation
@testable import SimulatorCore

/// A throwaway CoreSimulator `Devices` directory holding hand-written plist fixtures, so loading
/// can be exercised against known devices and apps instead of the machine's own simulators.
///
/// Mirrors `SimulatorManagerTests/Helpers/DeviceFixtureDirectory.swift`, plus installed apps.
struct DeviceFixtureDirectory {
    enum DeviceTypeIdentifier {
        static let iPhone = "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro"
        static let iPad = "com.apple.CoreSimulator.SimDeviceType.iPad-Air-11-inch-M3"
    }

    let url: URL

    init() throws {
        url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("simulator-core-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Writes the same keys a real `device.plist` carries, including the uppercase `UDID`.
    func writeDevice(
        udid: String,
        name: String,
        deviceTypeIdentifier: String = DeviceTypeIdentifier.iPhone
    ) throws {
        let plist: [String: Any] = [
            "UDID": udid,
            "name": name,
            "runtime": "com.apple.CoreSimulator.SimRuntime.iOS-26-1",
            "deviceType": deviceTypeIdentifier,
            "state": 1
        ]
        try write(plist, to: deviceURL(udid: udid).appendingPathComponent(SimulatorPaths.devicePlistName))
    }

    /// A device folder whose `device.plist` is missing entirely.
    func writeDeviceFolderWithoutPlist(udid: String) throws {
        try FileManager.default.createDirectory(at: deviceURL(udid: udid), withIntermediateDirectories: true)
    }

    /// A device folder whose `device.plist` is not a property list.
    func writeDeviceWithUnreadablePlist(udid: String) throws {
        let folder = deviceURL(udid: udid)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not a plist".utf8).write(to: folder.appendingPathComponent(SimulatorPaths.devicePlistName))
    }

    /// Installs an iOS app the way CoreSimulator lays it out: an `.app` bundle under
    /// `Containers/Bundle/Application` and a data container under `Containers/Data/Application`,
    /// tied together by the container metadata identifier.
    func writeApp(bundleIdentifier: String, name: String, onDeviceWithUdid udid: String) throws {
        let dataFolder = deviceURL(udid: udid).appendingPathComponent(SimulatorPaths.dataFolderName)

        let bundleURL = dataFolder
            .appendingPathComponent(SimulatorPaths.appBundleApplicationsPath)
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("\(name).app")
        try write([
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleName": name,
            "DTPlatformName": "iphonesimulator"
        ], to: bundleURL.appendingPathComponent(AppInfoPlist.infoPlistFileName))

        let containerURL = dataFolder
            .appendingPathComponent(SimulatorPaths.appDataApplicationsPath)
            .appendingPathComponent(UUID().uuidString)
        try write(["MCMMetadataIdentifier": bundleIdentifier],
                  to: containerURL.appendingPathComponent(MetaDataPlist.fileName))
    }

    func writeDSStore() throws {
        try Data().write(to: url.appendingPathComponent(".DS_Store"))
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }

    private func deviceURL(udid: String) -> URL {
        url.appendingPathComponent(udid, isDirectory: true)
    }

    private func write(_ plist: [String: Any], to fileURL: URL) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: fileURL)
    }
}
