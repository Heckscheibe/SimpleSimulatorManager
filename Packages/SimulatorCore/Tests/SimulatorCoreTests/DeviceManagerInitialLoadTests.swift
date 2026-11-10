import Combine
import Foundation
import Testing
@testable import SimulatorCore
import SimulatorCoreTestSupport

/// `SimulatorManagerApp` constructs the manager on the main thread at launch, and a full load
/// decodes every device, app and app-group plist. `init` therefore only schedules that load.
@Suite("DeviceManager initial load")
@MainActor
struct DeviceManagerInitialLoadTests {
    private let iPhoneUDID = "77777777-7777-7777-7777-777777777777"
    private let iPadUDID = "88888888-8888-8888-8888-888888888888"

    @Test("init returns before anything is loaded, and the first load publishes once")
    func initDoesNotLoadOnTheCallingThread() async throws {
        let fixture = try DeviceFixtureDirectory()
        defer { fixture.remove() }

        try fixture.writeDevice(udid: iPhoneUDID, name: "iPhone 16 Pro")
        try fixture.writeDevice(udid: iPadUDID,
                                name: "iPad Air 11-inch",
                                deviceTypeIdentifier: DeviceFixtureDirectory.DeviceTypeIdentifier.iPad)
        try fixture.writeApp(bundleIdentifier: "com.example.app", name: "Example", onDeviceWithUdid: iPhoneUDID)

        let manager = DeviceManager(devicesDirectoryURL: fixture.url)
        let recorder = Recorder(manager: manager)

        // The publish hops to the main queue, which this test holds until it suspends, so an
        // inline load would be the only way for anything to be visible here.
        #expect(recorder.devices == [[]])
        #expect(recorder.deviceTypes == [[]])
        #expect(recorder.recentApps == [[]])
        #expect(recorder.isLoading == [true])

        await manager.waitForInitialLoad()

        #expect(recorder.devices.count == 2)
        #expect(recorder.devices.last?.sorted() == [iPhoneUDID, iPadUDID].sorted())
        #expect(recorder.deviceTypes.count == 2)
        #expect(recorder.deviceTypes.last?.count == 2)
        #expect(recorder.recentApps.count == 2)
        #expect(recorder.recentApps.last?.map(\.app.bundleIdentifier) == ["com.example.app"])
        #expect(recorder.isLoading == [true, false])
        #expect(recorder.devicesPublishedOffMain == false)
    }

    @Test("Without a devices directory the load still finishes, publishing nothing")
    func missingDirectoryFinishesLoading() async {
        let manager = DeviceManager(devicesDirectoryURL: nil)
        let recorder = Recorder(manager: manager)

        await manager.waitForInitialLoad()

        #expect(recorder.devices == [[]])
        #expect(recorder.isLoading == [true, false])
    }

    @Test("A reload requested right after init publishes after the initial load")
    func reloadAfterInitPublishesLast() async throws {
        let fixture = try DeviceFixtureDirectory()
        defer { fixture.remove() }

        try fixture.writeDevice(udid: iPhoneUDID, name: "iPhone 16 Pro")

        let manager = DeviceManager(devicesDirectoryURL: fixture.url)
        let recorder = Recorder(manager: manager)

        await manager.resetAndLoadDevices()

        // Both loads went through the serial queue, so the initial one cannot land on top of the
        // reload: the loading flag is already cleared and the reload's snapshot is the last one.
        #expect(recorder.isLoading == [true, false])
        #expect(recorder.devices.count == 3)
        #expect(recorder.devices.last == [iPhoneUDID])
    }
}

// MARK: - Helpers

@MainActor
private final class Recorder {
    private(set) var devices: [[String]] = []
    private(set) var deviceTypes: [[DeviceType]] = []
    private(set) var recentApps: [[AppChange]] = []
    private(set) var isLoading: [Bool] = []
    private(set) var devicesPublishedOffMain = false
    private var cancellables: Set<AnyCancellable> = []

    init(manager: DeviceManager) {
        manager.devices
            .sink { [weak self] devices in
                self?.devices.append(devices.map(\.udid))
                if !Thread.isMainThread {
                    self?.devicesPublishedOffMain = true
                }
            }
            .store(in: &cancellables)
        manager.deviceTypes.sink { [weak self] in self?.deviceTypes.append($0) }.store(in: &cancellables)
        manager.recentInstalledApps.sink { [weak self] in self?.recentApps.append($0) }.store(in: &cancellables)
        manager.isLoadingInitialDevices.sink { [weak self] in self?.isLoading.append($0) }.store(in: &cancellables)
    }
}
