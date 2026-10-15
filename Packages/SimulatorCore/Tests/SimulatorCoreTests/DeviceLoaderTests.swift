import Combine
import Foundation
import Testing
@testable import SimulatorCore
import SimulatorCoreTestSupport

@Suite("DeviceLoader")
struct DeviceLoaderTests {
    private let iPhoneUDID = "11111111-1111-1111-1111-111111111111"
    private let iPadUDID = "22222222-2222-2222-2222-222222222222"

    // MARK: - Device list

    @Test("Device list decodes every readable device.plist")
    func deviceListDecodesDevices() throws {
        let fixture = try DeviceFixtureDirectory()
        defer { fixture.remove() }

        try fixture.writeDevice(udid: iPhoneUDID, name: "iPhone 16 Pro")
        try fixture.writeDevice(udid: iPadUDID,
                                name: "iPad Air 11-inch",
                                deviceTypeIdentifier: DeviceFixtureDirectory.DeviceTypeIdentifier.iPad)

        let devices = DeviceLoader(devicesDirectoryURL: fixture.url)
            .loadDeviceList()
            .sorted { $0.udid < $1.udid }

        #expect(devices.map(\.udid) == [iPhoneUDID, iPadUDID])
        #expect(devices.map(\.simulatorPlatform) == [.iPhone, .iPad])
        #expect(devices.allSatisfy { $0.osVersion == "iOS 26.1" })
        #expect(devices.allSatisfy { $0.url?.lastPathComponent == $0.udid })
    }

    @Test("Device list skips missing and unreadable device.plist files and .DS_Store")
    func deviceListSkipsBrokenEntries() throws {
        let fixture = try DeviceFixtureDirectory()
        defer { fixture.remove() }

        try fixture.writeDevice(udid: iPhoneUDID, name: "iPhone 16 Pro")
        try fixture.writeDeviceFolderWithoutPlist(udid: "33333333-3333-3333-3333-333333333333")
        try fixture.writeDeviceWithUnreadablePlist(udid: "44444444-4444-4444-4444-444444444444")
        try fixture.writeDSStore()

        let devices = DeviceLoader(devicesDirectoryURL: fixture.url).loadDeviceList()

        #expect(devices.map(\.udid) == [iPhoneUDID])
    }

    @Test("Device list does not scan apps")
    func deviceListDoesNotScanApps() throws {
        let fixture = try DeviceFixtureDirectory()
        defer { fixture.remove() }

        try fixture.writeDevice(udid: iPhoneUDID, name: "iPhone 16 Pro")
        try fixture.writeApp(bundleIdentifier: "com.example.app", name: "Example", onDeviceWithUdid: iPhoneUDID)

        let devices = DeviceLoader(devicesDirectoryURL: fixture.url).loadDeviceList()

        #expect(devices.count == 1)
        #expect(devices.first?.apps.isEmpty == true)
    }

    @Test("Device list is empty for a missing or unknown devices directory")
    func deviceListEmptyWithoutDirectory() {
        let missingURL = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString)")

        #expect(DeviceLoader(devicesDirectoryURL: missingURL).loadDeviceList().isEmpty)
        #expect(DeviceLoader(devicesDirectoryURL: nil).loadDeviceList().isEmpty)
    }

    // MARK: - Full load

    @Test("Full load returns nil when the devices directory is unknown")
    func fullLoadNilWithoutDirectory() {
        #expect(DeviceLoader(devicesDirectoryURL: nil).loadDevices() == nil)
    }

    @Test("Full load attaches apps and records an installed change per app")
    func fullLoadAttachesApps() throws {
        let fixture = try DeviceFixtureDirectory()
        defer { fixture.remove() }

        try fixture.writeDevice(udid: iPhoneUDID, name: "iPhone 16 Pro")
        try fixture.writeApp(bundleIdentifier: "com.example.first", name: "First", onDeviceWithUdid: iPhoneUDID)
        try fixture.writeApp(bundleIdentifier: "com.example.second", name: "Second", onDeviceWithUdid: iPhoneUDID)

        let loaded = try #require(DeviceLoader(devicesDirectoryURL: fixture.url).loadDevices())
        let device = try #require(loaded.devices.first)

        #expect(Set(device.apps.map(\.bundleIdentifier)) == ["com.example.first", "com.example.second"])
        #expect(Set(loaded.initialAppChanges.map(\.app.bundleIdentifier)) == ["com.example.first", "com.example.second"])
        #expect(loaded.initialAppChanges.allSatisfy { $0.changeType == .installed && $0.device.udid == iPhoneUDID })
    }

    @Test("Full load matches what DeviceManager publishes")
    @MainActor
    func fullLoadMatchesDeviceManager() throws {
        let fixture = try DeviceFixtureDirectory()
        defer { fixture.remove() }

        try fixture.writeDevice(udid: iPhoneUDID, name: "iPhone 16 Pro")
        try fixture.writeDevice(udid: iPadUDID,
                                name: "iPad Air 11-inch",
                                deviceTypeIdentifier: DeviceFixtureDirectory.DeviceTypeIdentifier.iPad)
        try fixture.writeApp(bundleIdentifier: "com.example.first", name: "First", onDeviceWithUdid: iPhoneUDID)
        try fixture.writeApp(bundleIdentifier: "com.example.second", name: "Second", onDeviceWithUdid: iPadUDID)

        let loaded = try #require(DeviceLoader(devicesDirectoryURL: fixture.url).loadDevices())

        let deviceManager = DeviceManager(devicesDirectoryURL: fixture.url)
        var cancellables: Set<AnyCancellable> = []
        var publishedDevices: [Device] = []
        var publishedRecentApps: [AppChange] = []
        deviceManager.devices.sink { publishedDevices = $0 }.store(in: &cancellables)
        deviceManager.recentInstalledApps.sink { publishedRecentApps = $0 }.store(in: &cancellables)

        #expect(publishedDevices.map(\.udid).sorted() == loaded.devices.map(\.udid).sorted())
        #expect(publishedDevices.flatMap { $0.apps.map(\.bundleIdentifier) }.sorted()
            == loaded.devices.flatMap { $0.apps.map(\.bundleIdentifier) }.sorted())
        #expect(publishedRecentApps.map(RecentApps.key(for:)) == RecentApps.initial(from: loaded.initialAppChanges).map(RecentApps.key(for:)))
        cancellables.removeAll()
    }

    @Test("Loading without app groups still loads apps and changes but skips the groups")
    func loadWithoutAppGroups() throws {
        let fixture = try DeviceFixtureDirectory()
        defer { fixture.remove() }

        try fixture.writeDevice(udid: iPhoneUDID, name: "iPhone 16 Pro")
        try fixture.writeApp(bundleIdentifier: "com.example.app", name: "Example", onDeviceWithUdid: iPhoneUDID)
        try fixture.writeAppGroup(identifier: "group.com.example.app", onDeviceWithUdid: iPhoneUDID)

        let loader = DeviceLoader(devicesDirectoryURL: fixture.url)
        let withGroups = try #require(loader.loadDevices())
        let withoutGroups = try #require(loader.loadDevices(includingAppGroups: false))

        #expect(withGroups.devices.first?.appGroups.map(\.identifier) == ["group.com.example.app"])
        #expect(withoutGroups.devices.first?.appGroups.isEmpty == true)
        #expect(withoutGroups.devices.first?.apps.map(\.bundleIdentifier) == ["com.example.app"])
        #expect(withoutGroups.initialAppChanges.count == withGroups.initialAppChanges.count)
    }

    // MARK: - Single device

    @Test("Single device load derives the folder from the UDID")
    func singleDeviceLoad() throws {
        let fixture = try DeviceFixtureDirectory()
        defer { fixture.remove() }

        try fixture.writeDevice(udid: iPhoneUDID, name: "iPhone 16 Pro")
        try fixture.writeApp(bundleIdentifier: "com.example.app", name: "Example", onDeviceWithUdid: iPhoneUDID)

        let loader = DeviceLoader(devicesDirectoryURL: fixture.url)
        let device = try #require(loader.loadDevice(withUdid: iPhoneUDID))

        #expect(device.name == "iPhone 16 Pro")
        #expect(device.apps.map(\.bundleIdentifier) == ["com.example.app"])
        #expect(loader.loadDevice(withUdid: "00000000-0000-0000-0000-000000000000") == nil)
    }
}
