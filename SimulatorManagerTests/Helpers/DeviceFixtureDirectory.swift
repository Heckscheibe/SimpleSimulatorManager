import Foundation
@testable import SimulatorManager

/// A throwaway CoreSimulator `Devices` directory holding hand-written `device.plist` fixtures,
/// so loading can be exercised against known devices instead of the machine's own simulators.
struct DeviceFixtureDirectory {
    enum DeviceTypeIdentifier {
        static let iPhone = "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro"
        static let iPad = "com.apple.CoreSimulator.SimDeviceType.iPad-Air-11-inch-M3"
        static let watch = "com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-11-46mm"
        static let appleTV = "com.apple.CoreSimulator.SimDeviceType.Apple-TV-4K-3rd-generation"
    }

    let url: URL

    init() throws {
        url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("device-manager-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Writes the same keys a real `device.plist` carries, including the uppercase `UDID`.
    func writeDevice(
        udid: String,
        name: String,
        deviceTypeIdentifier: String = DeviceTypeIdentifier.iPhone
    ) throws {
        let deviceURL = url.appendingPathComponent(udid, isDirectory: true)
        try FileManager.default.createDirectory(at: deviceURL, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "UDID": udid,
            "name": name,
            "runtime": "com.apple.CoreSimulator.SimRuntime.iOS-26-1",
            "deviceType": deviceTypeIdentifier,
            "state": 1
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: deviceURL.appendingPathComponent(SimulatorPaths.devicePlistName))
    }

    func removeDevice(udid: String) {
        try? FileManager.default.removeItem(at: url.appendingPathComponent(udid, isDirectory: true))
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
