import Combine
import Foundation
import Testing
@testable import SimulatorManager

/// Covers how `resetAndLoadDevices` is scheduled. A full reload decodes every device, app and
/// app-group plist, so it must not run inline on the caller — that call happens on the main actor
/// after a cleanup deletion and used to freeze the menu bar UI.
@Suite("DeviceManager reload scheduling")
struct DeviceManagerReloadTests {
    @Test("resetAndLoadDevices does not reload inline on the caller")
    @MainActor
    func resetAndLoadDevicesDoesNotLoadInline() async throws {
        let fixture = try DeviceFixtureDirectory()
        defer { fixture.remove() }

        try fixture.writeDevice(udid: "11111111-1111-1111-1111-111111111111", name: "iPhone 16 Pro")

        let deviceManager = DeviceManager(devicesDirectoryURL: fixture.url)
        var cancellables: Set<AnyCancellable> = []
        var publishedDevices: [[Device]] = []

        deviceManager.devices
            .sink { publishedDevices.append($0) }
            .store(in: &cancellables)

        #expect(publishedDevices.last?.count == 1)

        // A second device appears on disk, so an inline reload would be observable immediately.
        try fixture.writeDevice(udid: "22222222-2222-2222-2222-222222222222", name: "iPad Air 11-inch")

        let reload = Task { await deviceManager.resetAndLoadDevices() }

        // Still the pre-reload snapshot: a main-actor `Task` cannot start until this function
        // suspends, so nothing has been loaded on the caller.
        #expect(publishedDevices.last?.count == 1)

        await reload.value

        #expect(publishedDevices.last?.count == 2)
        cancellables.removeAll()
    }

    @Test("Reloaded devices are published on the main thread")
    @MainActor
    func reloadPublishesOnTheMainThread() async throws {
        let fixture = try DeviceFixtureDirectory()
        defer { fixture.remove() }

        try fixture.writeDevice(udid: "33333333-3333-3333-3333-333333333333", name: "iPhone 16 Pro")

        let deviceManager = DeviceManager(devicesDirectoryURL: fixture.url)
        var cancellables: Set<AnyCancellable> = []
        var publishThreadWasMain: [Bool] = []

        deviceManager.devices
            .sink { _ in publishThreadWasMain.append(Thread.isMainThread) }
            .store(in: &cancellables)

        try fixture.writeDevice(udid: "44444444-4444-4444-4444-444444444444", name: "iPad Air 11-inch")
        await deviceManager.resetAndLoadDevices()

        // Publisher values are only safe to mutate on the main queue, so the hop back matters.
        #expect(publishThreadWasMain.count > 1)
        #expect(publishThreadWasMain.allSatisfy { $0 })
        cancellables.removeAll()
    }
}

/// A throwaway CoreSimulator `Devices` directory holding hand-written `device.plist` fixtures.
private struct DeviceFixtureDirectory {
    let url: URL

    init() throws {
        url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("device-manager-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Writes the same keys a real `device.plist` carries, including the uppercase `UDID`.
    func writeDevice(udid: String, name: String) throws {
        let deviceURL = url.appendingPathComponent(udid, isDirectory: true)
        try FileManager.default.createDirectory(at: deviceURL, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "UDID": udid,
            "name": name,
            "runtime": "com.apple.CoreSimulator.SimRuntime.iOS-26-1",
            "deviceType": "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro",
            "state": 1
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: deviceURL.appendingPathComponent(SimulatorPaths.devicePlistName))
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
