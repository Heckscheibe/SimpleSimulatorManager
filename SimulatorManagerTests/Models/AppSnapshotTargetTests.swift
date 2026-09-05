import Foundation
import Testing
@testable import SimulatorManager

@Suite("Snapshot target resolution")
struct AppSnapshotTargetTests {
    @Test("Takes the app's containers, versions and device from what discovery already found")
    func resolvesFromDiscoveredValues() throws {
        let containerURL = URL(fileURLWithPath: "/tmp/container")
        let groupURL = URL(fileURLWithPath: "/tmp/group")
        let app = SimulatoriOSApp(displayName: "Acme",
                                  bundleIdentifier: "com.acme.app",
                                  appDocumentsFolderURL: containerURL,
                                  appPackageURL: URL(fileURLWithPath: "/tmp/Acme.app"),
                                  hasWatchApp: false,
                                  userDefaultsDomains: [],
                                  shortVersion: "3.1",
                                  buildVersion: "77")
        let device = TestDataHelpers.createMockDevice(udid: "UDID-9", name: "iPhone 17", osVersion: "iOS 26.1")
        device.apps = [app]
        device.appGroups = [
            AppGroup(identifier: "group.com.acme.app", uuid: "uuid-1", userDefaultsDomains: [], url: groupURL),
            AppGroup(identifier: "group.com.other.app", uuid: "uuid-2", userDefaultsDomains: [], url: groupURL)
        ]

        let target = try #require(AppSnapshotTarget(app: app, device: device))

        #expect(target.bundleIdentifier == "com.acme.app")
        #expect(target.appShortVersion == "3.1")
        #expect(target.appBuildVersion == "77")
        #expect(target.deviceUDID == "UDID-9")
        #expect(target.deviceName == "iPhone 17")
        #expect(target.osVersion == "iOS 26.1")
        #expect(target.dataContainerURL == containerURL)

        // Only the group whose identifier belongs to this app — the same rule discovery uses.
        try #require(target.appGroupContainers.count == 1)
        #expect(target.appGroupContainers[0].identifier == "group.com.acme.app")
    }

    @Test("Refuses an app with no data container")
    func refusesAppWithoutContainer() {
        let app = MockSimulatorApp(bundleIdentifier: "com.acme.app", displayName: "Acme")
        let device = TestDataHelpers.createMockDevice()

        #expect(AppSnapshotTarget(app: app, device: device) == nil)
    }

    @Test("Matches an app group to the app that shares its identifier")
    func associatesAppGroups() {
        let app = MockSimulatorApp(bundleIdentifier: "com.acme.app", displayName: "Acme")
        let matching = AppGroup(identifier: "group.com.acme.app", uuid: "uuid-1", userDefaultsDomains: [])
        let unrelated = AppGroup(identifier: "group.com.other.app", uuid: "uuid-2", userDefaultsDomains: [])
        // No dot, so `name` is empty — it must not match every app by accident.
        let malformed = AppGroup(identifier: "group", uuid: "uuid-3", userDefaultsDomains: [])

        #expect(matching.isAssociated(with: app))
        #expect(!unrelated.isAssociated(with: app))
        #expect(!malformed.isAssociated(with: app))
    }
}
