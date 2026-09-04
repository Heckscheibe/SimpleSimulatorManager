//
//  MenuTreeBuilderTests.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 04.09.26.
//

import Foundation
import Testing
@testable import SimulatorManager

@Suite("MenuTreeBuilder Tests")
@MainActor
struct MenuTreeBuilderTests {
    // MARK: - Top level

    @Test("The top level keeps the order and dividers the menu draws today")
    func topLevelOrderMatchesTheMenu() {
        let fixture = MenuTreeFixture()
        defer { fixture.tearDown() }

        let nodes = fixture.makeBuilder().makeNodes()

        #expect(nodes.identifiers == [
            "recentApps.empty",
            "divider.afterRecentApps",
            "divider.afterDeviceTypes",
            "settings.recentApps",
            "settings.divider",
            "settings.open",
            "divider.afterSettings",
            "cleanup",
            "divider.afterCleanup",
            "reset",
            "divider.afterReset",
            "github.project",
            "github.divider",
            "github.version",
            "divider.afterGitHub",
            "quit"
        ])
    }

    @Test("Settings… and Quit dispatch to the injected closures")
    func staticActionsDispatch() {
        let fixture = MenuTreeFixture()
        defer { fixture.tearDown() }

        let nodes = fixture.makeBuilder().makeNodes()
        nodes.node(withID: "settings.open")?.primaryAction?.perform()
        nodes.node(withID: "quit")?.primaryAction?.perform()

        #expect(fixture.openPreferencesCount == 1)
        #expect(fixture.quitCount == 1)
    }

    // MARK: - Recent apps

    @Test("The Recent Apps section is left out entirely when the preference is off")
    func recentAppsSectionIsOmittedWhenDisabled() async {
        let fixture = MenuTreeFixture()
        defer { fixture.tearDown() }

        await fixture.setRecentApps([TestDataHelpers.createMockAppChange()])
        fixture.settings.showRecentApps = false

        let nodes = fixture.makeBuilder().makeNodes()

        #expect(nodes.first?.id == "divider.afterRecentApps")
        #expect(nodes.node(withID: "recentApps.header") == nil)
        #expect(nodes.node(withID: "recentApps.empty") == nil)
    }

    @Test("An empty recent-apps list shows the No Recent Apps row instead of a header")
    func emptyRecentAppsShowsInformationalRow() {
        let fixture = MenuTreeFixture()
        defer { fixture.tearDown() }

        let nodes = fixture.makeBuilder().makeNodes()

        #expect(nodes.node(withID: "recentApps.header") == nil)
        #expect(nodes.node(withID: "recentApps.empty")?.title == "No Recent Apps")
        #expect(nodes.node(withID: "recentApps.empty")?.isSelectable == false)
    }

    @Test("A recent app is subtitled with the device it was installed on")
    func recentAppCarriesItsDevice() async throws {
        let fixture = MenuTreeFixture()
        defer { fixture.tearDown() }

        let device = TestDataHelpers.createMockDevice(udid: "device-1", name: "iPhone 16", osVersion: "18.2")
        let app = TestDataHelpers.createMockApp(bundleIdentifier: "com.test.weather", displayName: "Weather")
        await fixture.setRecentApps([TestDataHelpers.createMockAppChange(app: app, device: device)])

        let nodes = fixture.makeBuilder().makeNodes()
        let recentApp = try #require(nodes.node(withID: "recentApp.com.test.weather.device-1"))

        #expect(nodes.node(withID: "recentApps.header")?.title == "Recent Apps")
        #expect(recentApp.title == "Weather")
        #expect(recentApp.subtitle == "iPhone 16 18.2")
    }

    // MARK: - Device types and devices

    @Test("Device types the user has hidden do not appear")
    func hiddenPlatformsAreFilteredOut() async {
        let fixture = MenuTreeFixture()
        defer { fixture.tearDown() }

        await fixture.setDevices([
            TestDataHelpers.createiPhoneDevice(udid: "iphone-1", name: "iPhone 16"),
            TestDataHelpers.createAppleTVDevice(udid: "appletv-1", name: "Apple TV 4K")
        ])
        fixture.settings.showTVOS = false

        let nodes = fixture.makeBuilder().makeNodes()

        #expect(nodes.node(withID: "deviceType.iPhone 16") != nil)
        #expect(nodes.node(withID: "deviceType.Apple TV 4K") == nil)
    }

    @Test("Devices sharing a name are grouped under one device type")
    func devicesAreGroupedUnderTheirDeviceType() async throws {
        let fixture = MenuTreeFixture()
        defer { fixture.tearDown() }

        await fixture.setDevices([
            TestDataHelpers.createMockDevice(udid: "device-1", name: "iPhone 16 Pro", osVersion: "18.2"),
            TestDataHelpers.createMockDevice(udid: "device-2", name: "iPhone 16 Pro", osVersion: "18.1")
        ])

        let nodes = fixture.makeBuilder().makeNodes()
        let deviceType = try #require(nodes.node(withID: "deviceType.iPhone 16 Pro"))

        #expect(deviceType.children.contains { $0.id == "device.device-1.state" })
        #expect(deviceType.children.contains { $0.id == "device.device-2.state" })
    }

    @Test("A device with apps gets an OS-version submenu, one without gets informational rows")
    func deviceContentsDependOnInstalledApps() async throws {
        let fixture = MenuTreeFixture()
        defer { fixture.tearDown() }

        let withApps = TestDataHelpers.createMockDevice(udid: "with-apps", name: "iPhone 16", osVersion: "18.2")
        withApps.apps = [TestDataHelpers.createMockApp(bundleIdentifier: "com.test.one", displayName: "One")]
        let withoutApps = TestDataHelpers.createMockDevice(udid: "no-apps", name: "iPhone 16", osVersion: "18.1")
        await fixture.setDevices([withApps, withoutApps])

        let nodes = fixture.makeBuilder().makeNodes()
        let contents = try #require(nodes.node(withID: "device.with-apps.contents"))

        #expect(contents.title == "18.2")
        #expect(contents.isSubmenu)
        #expect(nodes.node(withID: "device.no-apps.contents") == nil)
        #expect(nodes.node(withID: "device.no-apps.osVersion")?.title == "18.1")
        #expect(nodes.node(withID: "device.no-apps.noApps")?.title == "No apps installed")
    }

    @Test("Erase Simulator is flagged destructive")
    func eraseIsDestructive() async throws {
        let fixture = MenuTreeFixture()
        defer { fixture.tearDown() }

        await fixture.setDevices([TestDataHelpers.createMockDevice(udid: "device-1", name: "iPhone 16")])

        let erase = try #require(fixture.makeBuilder().makeNodes().node(withID: "device.device-1.erase"))

        #expect(erase.title == "Erase Simulator")
        #expect(erase.isDestructive)
    }

    @Test("Folder rows appear only for folders that exist on disk")
    func deviceFolderRowsFollowTheFilesystem() async throws {
        let fixture = MenuTreeFixture()
        defer { fixture.tearDown() }

        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let withoutFolders = TestDataHelpers.createMockDevice(udid: "bare", name: "iPhone 16")
        let withFolders = TestDataHelpers.createMockDevice(udid: "full", name: "iPhone 16")
        withFolders.url = root
        try FileManager.default.createDirectory(at: #require(withFolders.appDataFolder),
                                                withIntermediateDirectories: true)
        await fixture.setDevices([withoutFolders, withFolders])

        let nodes = fixture.makeBuilder().makeNodes()

        #expect(nodes.node(withID: "device.bare.simulatorFolder") != nil)
        #expect(nodes.node(withID: "device.bare.appFolder") == nil)
        #expect(nodes.node(withID: "device.bare.appPackageFolder") == nil)
        #expect(nodes.node(withID: "device.full.appFolder")?.title == "App Folder")
        #expect(nodes.node(withID: "device.full.appPackageFolder") == nil)
    }

    // MARK: - Apps and app groups

    @Test("An app carries its folder actions as secondary actions and as drill-down rows")
    func appNodesCarryTheirFolderActions() async throws {
        let fixture = MenuTreeFixture()
        defer { fixture.tearDown() }

        let device = TestDataHelpers.createMockDevice(udid: "device-1", name: "iPhone 16")
        device.apps = [
            TestDataHelpers.createMockApp(bundleIdentifier: "com.test.plain", displayName: "Plain"),
            TestDataHelpers.createMockApp(bundleIdentifier: "com.test.prefs",
                                          displayName: "Prefs",
                                          userDefaultsDomains: ["com.test.prefs"])
        ]
        await fixture.setDevices([device])

        let nodes = fixture.makeBuilder().makeNodes()
        let plain = try #require(nodes.node(withID: "device.device-1.app.com.test.plain"))
        let prefs = try #require(nodes.node(withID: "device.device-1.app.com.test.prefs"))

        #expect(plain.primaryAction?.title == "Documents Folder")
        #expect(plain.secondaryActions.map(\.title) == ["App Package"])
        #expect(plain.children.titles == ["Documents Folder", "App Package"])
        #expect(prefs.secondaryActions.map(\.title) == ["App Package", "User Defaults"])
        #expect(prefs.children.titles == ["Documents Folder", "App Package", "User Defaults"])
    }

    @Test("App groups get a header and their Group UserDefaults row only when they have one")
    func appGroupNodesFollowTheirContents() async throws {
        let fixture = MenuTreeFixture()
        defer { fixture.tearDown() }

        let device = TestDataHelpers.createMockDevice(udid: "device-1", name: "iPhone 16")
        device.apps = [TestDataHelpers.createMockApp()]
        device.appGroups = [
            AppGroup(identifier: "group.com.test.plain", uuid: "uuid-1", userDefaultsDomains: []),
            AppGroup(identifier: "group.com.test.prefs", uuid: "uuid-2", userDefaultsDomains: ["group.com.test.prefs"])
        ]
        await fixture.setDevices([device])

        let nodes = fixture.makeBuilder().makeNodes()
        let plain = try #require(nodes.node(withID: "device.device-1.appGroup.group.com.test.plain"))
        let prefs = try #require(nodes.node(withID: "device.device-1.appGroup.group.com.test.prefs"))

        #expect(nodes.node(withID: "device.device-1.appGroups.header")?.title == "AppGroups")
        #expect(plain.title == "Group com.test.plain")
        #expect(plain.children.titles == ["Group Folder"])
        #expect(prefs.children.titles == ["Group Folder", "Group UserDefaults"])
    }

    // MARK: - Settings toggles

    @Test("A platform toggle appears only when a simulator of that platform exists")
    func platformTogglesFollowAvailableDevices() async {
        let fixture = MenuTreeFixture()
        defer { fixture.tearDown() }

        await fixture.setDevices([
            TestDataHelpers.createiPhoneDevice(udid: "iphone-1", name: "iPhone 16"),
            TestDataHelpers.createWatchDevice(udid: "watch-1", name: "Apple Watch Series 9")
        ])

        let nodes = fixture.makeBuilder().makeNodes()

        #expect(nodes.node(withID: "settings.iOS") != nil)
        #expect(nodes.node(withID: "settings.watchOS") != nil)
        #expect(nodes.node(withID: "settings.iPadOS") == nil)
        #expect(nodes.node(withID: "settings.tvOS") == nil)
        #expect(nodes.node(withID: "settings.visionOS") == nil)
    }

    // MARK: - Reset, cleanup and GitHub

    @Test("Resetting replaces the confirm action with a progress row and disables the submenu")
    func resetShowsProgressWhileRunning() throws {
        let fixture = MenuTreeFixture()
        defer { fixture.tearDown() }

        let idle = try #require(fixture.makeBuilder().makeNodes().node(withID: "reset"))
        #expect(idle.isEnabled)
        #expect(idle.children.identifiers == ["reset.confirm"])
        #expect(idle.children.first?.isDestructive == true)

        fixture.resetViewModel.isResettingSimulators = true

        let running = try #require(fixture.makeBuilder().makeNodes().node(withID: "reset"))
        #expect(!running.isEnabled)
        #expect(running.title == "Resetting...")
        #expect(running.children.identifiers == ["reset.progress"])
    }

    @Test("Cleanup lists its candidate groups, and disables its actions while deleting")
    func cleanupReflectsItsViewModel() throws {
        let fixture = MenuTreeFixture()
        defer { fixture.tearDown() }

        let candidate = makeCleanupCandidate(id: "candidate-1", name: "Broken iPhone", osVersion: "17.0")
        fixture.cleanupViewModel.cleanupCandidates = [candidate]

        let nodes = fixture.makeBuilder().makeNodes()
        let deleteAll = try #require(nodes.node(withID: "cleanup.deleteAll"))

        #expect(deleteAll.title == "Cleanup All Simulators (1)")
        #expect(deleteAll.isDestructive)
        #expect(deleteAll.isEnabled)
        #expect(nodes.node(withID: "cleanup.candidate.candidate-1")?.title == "Broken iPhone")
        #expect(nodes.node(withID: "cleanup.candidate.candidate-1.osVersion")?.title == "OS: 17.0")
        #expect(nodes.node(withID: "cleanup.candidate.candidate-1.delete")?.isDestructive == true)

        fixture.cleanupViewModel.deletingCandidateIDs = ["candidate-1"]

        let deleting = fixture.makeBuilder().makeNodes()

        #expect(deleting.node(withID: "cleanup.deleteAll")?.title == "Cleaning Up All…")
        #expect(deleting.node(withID: "cleanup.deleteAll")?.isEnabled == false)
        #expect(deleting.node(withID: "cleanup.deleteAll")?.isSelectable == false)
        #expect(deleting.node(withID: "cleanup.refresh")?.isEnabled == false)
    }

    @Test("An empty cleanup scan says so, and offers neither a delete-all nor any groups")
    func cleanupWithoutCandidates() {
        let fixture = MenuTreeFixture()
        defer { fixture.tearDown() }

        let nodes = fixture.makeBuilder().makeNodes()

        #expect(nodes.node(withID: "cleanup.empty")?.title == "No invalid simulators found")
        #expect(nodes.node(withID: "cleanup.deleteAll") == nil)
        #expect(nodes.node(withID: "cleanup.explanation") != nil)
        #expect(nodes.node(withID: "cleanup.refresh")?.isEnabled == true)
    }

    @Test("An available update replaces the version row with an actionable one")
    func gitHubSectionFollowsUpdateAvailability() throws {
        let fixture = MenuTreeFixture()
        defer { fixture.tearDown() }

        #expect(fixture.makeBuilder().makeNodes().node(withID: "github.version")?.title == "Version 1.4.0")

        fixture.githubService.isUpdateAvailable = true

        let nodes = fixture.makeBuilder().makeNodes()
        let update = try #require(nodes.node(withID: "github.update"))

        #expect(update.title == "Update Available")
        #expect(update.subtitle == "Version 1.4.0")
        #expect(update.iconName == "info.circle.fill")
        #expect(nodes.node(withID: "github.version") == nil)
    }

    @Test("Without a bundle version the GitHub section is just the project link")
    func gitHubSectionWithoutAVersion() {
        let fixture = MenuTreeFixture()
        defer { fixture.tearDown() }

        let nodes = fixture.makeBuilder(appVersion: nil).makeNodes()

        #expect(nodes.node(withID: "github.project") != nil)
        #expect(nodes.node(withID: "github.divider") == nil)
        #expect(nodes.node(withID: "github.version") == nil)
    }

    // MARK: - Device actions in flight

    @Test("A running device action replaces the erase row and its error surfaces afterwards")
    func deviceActionProgressAndErrorAreShown() async {
        let resetService = GatedResetService()
        let fixture = MenuTreeFixture(resetService: resetService)
        defer { fixture.tearDown() }

        let device = TestDataHelpers.createMockDevice(udid: "device-1", name: "iPhone 16")
        await fixture.setDevices([device])

        let deviceViewModel = fixture.simulatorManagerViewModel.makeDeviceViewModel(for: device)
        deviceViewModel.eraseDevice()
        await waitUntil { deviceViewModel.isPerformingAction }

        let running = fixture.makeBuilder().makeNodes()
        #expect(running.node(withID: "device.device-1.erase") == nil)
        #expect(running.node(withID: "device.device-1.actionProgress")?.title == deviceViewModel.currentActionTitle)

        // The mock device manager cannot refresh a device it was never given, so finishing the
        // erase leaves the view model reporting the failure — which is what puts the error row back
        // into the menu.
        resetService.release()
        await waitUntil { deviceViewModel.actionErrorMessage != nil }

        let finished = fixture.makeBuilder().makeNodes()
        #expect(finished.node(withID: "device.device-1.erase") != nil)
        #expect(finished.node(withID: "device.device-1.error")?.title == deviceViewModel.actionErrorMessage)
    }

    // MARK: - Identity

    @Test("Rebuilding with unchanged state produces identical identifiers")
    func identifiersAreStableAcrossRebuilds() async {
        let fixture = MenuTreeFixture()
        defer { fixture.tearDown() }

        let device = TestDataHelpers.createMockDevice(udid: "device-1", name: "iPhone 16")
        device.apps = [TestDataHelpers.createMockApp(bundleIdentifier: "com.test.one", displayName: "One")]
        await fixture.setDevices([device])

        let first = allIdentifiers(of: fixture.makeBuilder().makeNodes())
        let second = allIdentifiers(of: fixture.makeBuilder().makeNodes())

        #expect(first == second)
        #expect(!first.isEmpty)
    }

    @Test("Refreshing one device does not disturb the identifiers of the others")
    func identifiersSurviveADeviceRefresh() async {
        let fixture = MenuTreeFixture()
        defer { fixture.tearDown() }

        let stable = TestDataHelpers.createMockDevice(udid: "stable", name: "iPhone 16", osVersion: "18.2")
        let refreshed = TestDataHelpers.createMockDevice(udid: "refreshed", name: "iPhone 16", osVersion: "18.1")
        await fixture.setDevices([stable, refreshed])

        let before = allIdentifiers(of: fixture.makeBuilder().makeNodes())

        // A refresh replaces the Device instance while keeping its UDID, and republishes the whole
        // array — exactly what happens after an erase or an app-folder change.
        let replacement = TestDataHelpers.createMockDevice(udid: "refreshed", name: "iPhone 16", osVersion: "18.1")
        await fixture.setDevices([stable, replacement])

        #expect(allIdentifiers(of: fixture.makeBuilder().makeNodes()) == before)
    }
}

// MARK: - Helpers

private extension MenuTreeBuilderTests {
    func allIdentifiers(of nodes: [MenuNode]) -> [String] {
        nodes.flatMap { [$0.id] + allIdentifiers(of: $0.children) }
    }

    func makeCleanupCandidate(id: String, name: String, osVersion: String) -> SimulatorCleanupCandidate {
        SimulatorCleanupCandidate(id: id,
                                  name: name,
                                  udid: id,
                                  simulatorPlatform: .iPhone,
                                  osVersion: osVersion,
                                  lastBootedAt: nil,
                                  diskUsageBytes: nil,
                                  reasons: [.missingRuntime],
                                  detailMessage: nil,
                                  deletionMethod: .simctlDelete(id))
    }
}
