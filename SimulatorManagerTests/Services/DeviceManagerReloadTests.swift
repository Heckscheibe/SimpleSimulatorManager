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

        deviceManager.resetAndLoadDevices()

        // Still the pre-reload snapshot: the call only scheduled the work.
        #expect(publishedDevices.last?.count == 1)

        try await waitUntil { publishedDevices.last?.count == 2 }

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
        deviceManager.resetAndLoadDevices()

        try await waitUntil { publishThreadWasMain.count > 1 }

        // Publisher values are only safe to mutate on the main queue, so the hop back matters.
        #expect(publishThreadWasMain.allSatisfy { $0 })
        cancellables.removeAll()
    }

    // MARK: - Helpers

    /// Polls instead of sleeping a fixed interval, so the suite stays fast and does not depend on
    /// how loaded the machine is while the rest of the tests run in parallel.
    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout

        while ContinuousClock.now < deadline {
            if await MainActor.run(body: condition) {
                return
            }

            try await Task.sleep(for: .milliseconds(10))
        }

        Issue.record("Timed out waiting for the expected condition")
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
