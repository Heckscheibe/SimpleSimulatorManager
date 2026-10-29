import Foundation
import Testing
@testable import SimulatorCore

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
        let device = Device(udid: "UDID-9", name: "iPhone 17", state: .running, simulatorPlatform: .iPhone, osVersion: "iOS 26.1")
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
        let app = Self.app(appDocumentsFolderURL: nil)
        let device = Device(udid: "UDID-1", name: "iPhone 17", state: .running, simulatorPlatform: .iPhone, osVersion: "iOS 26.1")

        #expect(AppSnapshotTarget(app: app, device: device) == nil)
    }

    @Test("Matches an app group to the app that shares its identifier, as discovery does")
    func associatesAppGroups() {
        let app = Self.app(appDocumentsFolderURL: URL(fileURLWithPath: "/tmp/container"))
        let matching = AppGroup(identifier: "group.com.acme.app", uuid: "uuid-1", userDefaultsDomains: [])
        let unrelated = AppGroup(identifier: "group.com.other.app", uuid: "uuid-2", userDefaultsDomains: [])
        // A group named after a whole dot-separated prefix of the bundle identifier belongs to it…
        let prefix = AppGroup(identifier: "group.com.acme", uuid: "uuid-3", userDefaultsDomains: [])
        // …but not to an app whose identifier merely contains that name as a substring.
        let lookalikeApp = Self.app(bundleIdentifier: "com.acmeplus.app",
                                    appDocumentsFolderURL: URL(fileURLWithPath: "/tmp/container"))
        // No dot, so `name` is empty — it must not match every app by accident.
        let malformed = AppGroup(identifier: "group", uuid: "uuid-4", userDefaultsDomains: [])
        let groups = [matching, unrelated, prefix, malformed]

        #expect(AppGroup.groups(in: groups, associatedWith: app).map(\.identifier)
            == ["group.com.acme.app", "group.com.acme"])
        #expect(AppGroup.groups(in: groups, associatedWith: lookalikeApp).isEmpty)
    }

    private static func app(
        bundleIdentifier: String = "com.acme.app",
        appDocumentsFolderURL: URL?
    ) -> SimulatoriOSApp {
        SimulatoriOSApp(displayName: "Acme",
                        bundleIdentifier: bundleIdentifier,
                        appDocumentsFolderURL: appDocumentsFolderURL,
                        appPackageURL: nil,
                        hasWatchApp: false,
                        userDefaultsDomains: [])
    }
}
