import Combine
import Foundation
import Testing
@testable import SimulatorManager
@testable import SimulatorCore

/// The "hide UI test runner apps" preference, from the stored value down to what each list shows.
@Suite("UI test runner visibility")
@MainActor
struct TestRunnerVisibilityTests {
    // MARK: - Settings

    @Test("Runners are hidden on a fresh installation")
    func hiddenByDefault() {
        let suite = Suite()
        defer { suite.tearDown() }

        let settings = Settings(userDefaults: suite.userDefaults)

        #expect(settings.hideTestRunnerApps)
        #expect(!settings.showTestRunnerApps)
    }

    @Test("The choice survives a relaunch, and the positive reading mirrors it")
    func persistsAcrossRelaunch() {
        let suite = Suite()
        defer { suite.tearDown() }

        Settings(userDefaults: suite.userDefaults).showTestRunnerApps = true

        let relaunched = Settings(userDefaults: suite.userDefaults)

        #expect(!relaunched.hideTestRunnerApps)
        #expect(relaunched.showTestRunnerApps)
    }

    // MARK: - Recent apps

    @Test("Hidden runners take no slots in the capped recent-apps list")
    func runnersDoNotConsumeCapSlots() async {
        let recorder = Recorder(hidesTestRunnerApps: true)
        let device = TestDataHelpers.createMockDevice(udid: "device-1")
        let now = Date()
        let runners = (0 ..< 25).map { index in
            change("com.test.UITests\(index).xctrunner", on: device, at: now.addingTimeInterval(TimeInterval(1000 + index)), isTestRunner: true)
        }
        let regular = (0 ..< 25).map { index in
            change("com.test.app\(index)", on: device, at: now.addingTimeInterval(TimeInterval(index)))
        }

        recorder.manager.updateRecentApps(runners + regular)
        await drainMainQueue()

        #expect(recorder.latest.count == RecentApps.maxCount)
        #expect(recorder.latest.allSatisfy { !$0.app.isTestRunner })
        #expect(recorder.latest.first?.app.bundleIdentifier == "com.test.app24")
    }

    @Test("Toggling the preference restores and removes runners without a reload")
    func togglingRederivesTheList() async {
        let recorder = Recorder(hidesTestRunnerApps: true)
        let device = TestDataHelpers.createMockDevice(udid: "device-1")
        let now = Date()

        recorder.manager.updateRecentApps([
            change("com.test.UITests.xctrunner", on: device, at: now, isTestRunner: true),
            change("com.test.app", on: device, at: now.addingTimeInterval(-60))
        ])
        await drainMainQueue()
        #expect(recorder.bundleIdentifiers == ["com.test.app"])

        recorder.manager.setHidesTestRunnerApps(false)
        await drainMainQueue()
        #expect(recorder.bundleIdentifiers == ["com.test.UITests.xctrunner", "com.test.app"])

        recorder.manager.setHidesTestRunnerApps(true)
        await drainMainQueue()
        #expect(recorder.bundleIdentifiers == ["com.test.app"])
    }

    @Test("Runners that arrive while hidden come back when shown")
    func hiddenRunnersAreStillTracked() async {
        let recorder = Recorder(hidesTestRunnerApps: true)
        let device = TestDataHelpers.createMockDevice(udid: "device-1")

        recorder.manager.updateRecentApps([change("com.test.UITests.xctrunner", on: device, at: Date(), isTestRunner: true)])
        await drainMainQueue()
        #expect(recorder.latest.isEmpty)

        recorder.manager.setHidesTestRunnerApps(false)
        await drainMainQueue()

        #expect(recorder.bundleIdentifiers == ["com.test.UITests.xctrunner"])
    }

    @Test("Showing runners keeps the cap")
    func shownRunnersAreCapped() async {
        let recorder = Recorder(hidesTestRunnerApps: false)
        let device = TestDataHelpers.createMockDevice(udid: "device-1")
        let now = Date()
        let changes = (0 ..< 30).map { index in
            change("com.test.UITests\(index).xctrunner", on: device, at: now.addingTimeInterval(TimeInterval(index)), isTestRunner: true)
        }

        recorder.manager.updateRecentApps(changes)
        await drainMainQueue()

        #expect(recorder.latest.count == RecentApps.maxCount)
    }

    // MARK: - Device apps

    @Test("A device's apps list leaves runners out while the device keeps them")
    func deviceViewModelFiltersApps() {
        let device = TestDataHelpers.createMockDevice()
        device.apps = [
            TestDataHelpers.createMockApp(bundleIdentifier: "com.test.app"),
            TestDataHelpers.createMockApp(bundleIdentifier: "com.test.UITests.xctrunner", isTestRunner: true)
        ]
        let viewModel = DeviceViewModel(device: device,
                                        deviceManager: MockDeviceManager(),
                                        simulatorResetService: MockSimulatorDeviceActionService(),
                                        hidesTestRunnerApps: true)

        #expect(viewModel.apps.map(\.bundleIdentifier) == ["com.test.app"])

        viewModel.hidesTestRunnerApps = false

        #expect(viewModel.apps.map(\.bundleIdentifier) == ["com.test.app", "com.test.UITests.xctrunner"])
        #expect(device.apps.count == 2)
    }

    @Test("A device holding only hidden runners reads as having no apps")
    func onlyRunnersMeansNoApps() {
        let device = TestDataHelpers.createMockDevice()
        device.apps = [TestDataHelpers.createMockApp(bundleIdentifier: "com.test.UITests.xctrunner", isTestRunner: true)]
        let viewModel = DeviceViewModel(device: device,
                                        deviceManager: MockDeviceManager(),
                                        simulatorResetService: MockSimulatorDeviceActionService(),
                                        hidesTestRunnerApps: true)

        #expect(!viewModel.hasAppsInstalled)
    }

    // MARK: - Wiring

    @Test("The preference reaches the device manager and the device view models")
    func settingsDriveTheDeviceManager() async {
        let suite = Suite()
        defer { suite.tearDown() }
        let settings = Settings(userDefaults: suite.userDefaults)
        let deviceManager = MockDeviceManager()
        let viewModel = SimulatorManagerViewModel(deviceManager: deviceManager,
                                                  simulatorResetService: MockSimulatorDeviceActionService(),
                                                  deviceAppMonitoringService: MockDeviceAppMonitoringService(),
                                                  settings: settings)
        let device = TestDataHelpers.createMockDevice()
        // A device the manager does not know is pruned from the view model's cache on the next sync,
        // so let the manager's device list land before asking for the view model.
        deviceManager.setMockDevices([device])
        await drainMainQueue()
        let deviceViewModel = viewModel.makeDeviceViewModel(for: device)
        await drainMainQueue()

        #expect(deviceManager.lastHidesTestRunnerApps == true)
        #expect(deviceViewModel.hidesTestRunnerApps)

        settings.showTestRunnerApps = true
        await drainMainQueue()

        #expect(deviceManager.lastHidesTestRunnerApps == false)
        #expect(!deviceViewModel.hidesTestRunnerApps)
        #expect(!viewModel.makeDeviceViewModel(for: device).hidesTestRunnerApps)
    }

    // MARK: - Menu

    @Test("The menu entry is offered only when a runner is installed, and flips with the preference")
    func menuEntryIsGatedOnRelevance() async {
        let fixture = MenuTreeFixture()
        defer { fixture.tearDown() }

        let plain = TestDataHelpers.createMockDevice(udid: "device-1")
        plain.apps = [TestDataHelpers.createMockApp(bundleIdentifier: "com.test.app")]
        await fixture.setDevices([plain])

        #expect(fixture.makeBuilder().settingsNodes().node(withID: "settings.testRunners") == nil)

        plain.apps.append(TestDataHelpers.createMockApp(bundleIdentifier: "com.test.UITests.xctrunner", isTestRunner: true))
        await fixture.setDevices([plain])

        #expect(fixture.makeBuilder().settingsNodes().node(withID: "settings.testRunners")?.title == "Show UI Test Runners")

        fixture.settings.showTestRunnerApps = true

        let node = fixture.makeBuilder().settingsNodes().node(withID: "settings.testRunners")
        #expect(node?.title == "Hide UI Test Runners")

        node?.primaryAction?.perform()

        #expect(fixture.settings.hideTestRunnerApps)
    }

    // MARK: - Search

    @Test("Search leaves hidden runners out of its index")
    func searchHonoursThePreference() {
        let device = TestDataHelpers.createMockDevice(udid: "device-1", name: "iPhone 16")
        device.apps = [
            TestDataHelpers.createMockApp(bundleIdentifier: "com.test.app", displayName: "Fitness"),
            TestDataHelpers.createMockApp(bundleIdentifier: "com.test.UITests.xctrunner", displayName: "FitnessUITests-Runner", isTestRunner: true)
        ]
        let service = MenuSearchService()

        service.updateIndex(devices: [device], recentApps: [], visiblePlatforms: [.iPhone], hidesTestRunnerApps: true)
        #expect(service.results(for: "fitness").count == 1)

        service.updateIndex(devices: [device], recentApps: [], visiblePlatforms: [.iPhone], hidesTestRunnerApps: false)
        #expect(service.results(for: "fitness").count == 2)
    }
}

// MARK: - Helpers

private extension TestRunnerVisibilityTests {
    struct Suite {
        let name = "TestRunnerVisibilityTests.\(UUID().uuidString)"

        var userDefaults: UserDefaults? {
            UserDefaults(suiteName: name)
        }

        func tearDown() {
            UserDefaults.standard.removePersistentDomain(forName: name)
        }
    }

    @MainActor
    final class Recorder {
        let manager: DeviceManager
        private(set) var latest: [AppChange] = []
        private var cancellable: AnyCancellable?

        init(hidesTestRunnerApps: Bool) {
            manager = DeviceManager(devicesDirectoryURL: nil, hidesTestRunnerApps: hidesTestRunnerApps)
            cancellable = manager.recentInstalledApps.sink { [weak self] changes in
                self?.latest = changes
            }
        }

        var bundleIdentifiers: [String] {
            latest.map(\.app.bundleIdentifier)
        }
    }

    func change(_ bundleIdentifier: String, on device: Device, at timestamp: Date, isTestRunner: Bool = false) -> AppChange {
        AppChange(app: TestDataHelpers.createMockApp(bundleIdentifier: bundleIdentifier, isTestRunner: isTestRunner),
                  device: device,
                  changeType: .installed,
                  timestamp: timestamp)
    }
}
