import Foundation
import Testing
@testable import SimulatorCore
import SimulatorCoreTestSupport

/// `AppGroup.belongs(to:)` — the entitlement when discovery could read it, the group's name when not.
@Suite("App group association")
struct AppGroupAssociationTests {
    private let udid = "11111111-1111-1111-1111-111111111111"

    @Test("A group named after the app belongs to it, by entitlement or by name")
    func exactMatch() {
        let group = Self.group("group.com.acme.notes")

        #expect(group.belongs(to: Self.app("com.acme.notes", groups: ["group.com.acme.notes"])))
        #expect(group.belongs(to: Self.app("com.acme.notes", groups: nil)))
    }

    @Test("A suffix-named group belongs to the app whose entitlement claims it")
    func suffixNamedGroup() {
        let group = Self.group("group.com.acme.notes.shared")

        #expect(group.belongs(to: Self.app("com.acme.notes", groups: ["group.com.acme.notes.shared"])))
        // The name rule alone cannot see it — the case entitlements were brought in for.
        #expect(!group.belongs(to: Self.app("com.acme.notes", groups: nil)))
    }

    @Test("A shared parent group belongs only to the siblings that claim it; unknown ones fall back to the name")
    func sharedParentGroup() {
        let parent = Self.group("group.com.acme")
        let claiming = Self.app("com.acme.notes", groups: ["group.com.acme", "group.com.acme.notes"])
        let notClaiming = Self.app("com.acme.mail", groups: ["group.com.acme.mail"])
        let unknown = Self.app("com.acme.calendar", groups: nil)

        #expect(parent.belongs(to: claiming))
        #expect(!parent.belongs(to: notClaiming))
        #expect(parent.belongs(to: unknown))
        #expect(AppGroup.groups(in: [parent], associatedWith: notClaiming).isEmpty)
    }

    @Test("Known entitlements without app groups claim nothing, not even a group named after the app")
    func emptyEntitlementClaimsNothing() {
        #expect(!Self.group("group.com.acme.notes").belongs(to: Self.app("com.acme.notes", groups: [])))
    }

    @Test("A group with no dot in its identifier matches only an entitlement that lists it")
    func identifierWithoutDot() {
        let group = Self.group("acmegroup")

        #expect(group.belongs(to: Self.app("com.acme.notes", groups: ["acmegroup"])))
        // No dot leaves the name empty, which must not match every app by accident.
        #expect(!group.belongs(to: Self.app("com.acme.notes", groups: nil)))
        #expect(!group.belongs(to: Self.app("acmegroup", groups: nil)))
    }

    // MARK: - Discovery and snapshots

    @Test("Discovery reads each app's application groups from its executable once")
    func discoveryReadsEntitlements() throws {
        let fixture = try DeviceFixtureDirectory()
        defer { fixture.remove() }

        try fixture.writeDevice(udid: udid, name: "iPhone 16 Pro")
        try fixture.writeApp(bundleIdentifier: "com.acme.notes", name: "Notes", onDeviceWithUdid: udid,
                             applicationGroupsEntitlement: ["group.com.acme.notes.shared"])
        try fixture.writeApp(bundleIdentifier: "com.acme.legacy", name: "Legacy", onDeviceWithUdid: udid)

        let device = try #require(DeviceLoader(devicesDirectoryURL: fixture.url).loadDevice(withUdid: udid))
        let groupsByApp = Dictionary(uniqueKeysWithValues: device.apps.map { ($0.bundleIdentifier, $0.applicationGroupIdentifiers) })

        #expect(groupsByApp["com.acme.notes"] == .some(["group.com.acme.notes.shared"]))
        #expect(groupsByApp["com.acme.legacy"] == .some(nil))
    }

    @Test("Discovery keeps a suffix-named group an entitlement claims, and still hides Apple's and unclaimed ones")
    func discoveryKeepsClaimedGroups() throws {
        let fixture = try DeviceFixtureDirectory()
        defer { fixture.remove() }

        try fixture.writeDevice(udid: udid, name: "iPhone 16 Pro")
        try fixture.writeApp(bundleIdentifier: "com.acme.notes", name: "Notes", onDeviceWithUdid: udid,
                             applicationGroupsEntitlement: ["group.com.acme.notes.shared"])
        // Its groups are unknown, so the name rule still decides for it.
        try fixture.writeApp(bundleIdentifier: "com.other.app", name: "Other", onDeviceWithUdid: udid)
        try fixture.writeAppGroup(identifier: "group.com.acme.notes.shared", onDeviceWithUdid: udid)
        try fixture.writeAppGroup(identifier: "group.com.other.app", onDeviceWithUdid: udid)
        // Named after Notes, but Notes's entitlement does not list it, so nothing uses it.
        try fixture.writeAppGroup(identifier: "group.com.acme.notes", onDeviceWithUdid: udid)
        try fixture.writeAppGroup(identifier: "group.com.apple.notes", onDeviceWithUdid: udid)
        try fixture.writeAppGroup(identifier: "systemgroup.com.apple.configurationprofiles", onDeviceWithUdid: udid)

        let device = try #require(DeviceLoader(devicesDirectoryURL: fixture.url).loadDevice(withUdid: udid))

        #expect(Set(device.appGroups.map(\.identifier)) == ["group.com.acme.notes.shared", "group.com.other.app"])

        let notes = try #require(device.apps.first { $0.bundleIdentifier == "com.acme.notes" })
        let target = try #require(AppSnapshotTarget(app: notes, device: device))
        #expect(target.appGroupContainers.map(\.identifier) == ["group.com.acme.notes.shared"])
        #expect(target.appGroupContainers.first?.url == device.appGroups.first { $0.identifier == "group.com.acme.notes.shared" }?.url)
    }

    @Test("A restore warns about a suffix-named group the snapshot does not hold, now that the target knows it")
    func restoreReportsClaimedGroupMissingFromSnapshot() async throws {
        let fixture = try DeviceFixtureDirectory()
        let storeFixture = try SnapshotStoreFixtureDirectory()
        defer {
            fixture.remove()
            storeFixture.remove()
        }

        try fixture.writeDevice(udid: udid, name: "iPhone 16 Pro")
        try fixture.writeApp(bundleIdentifier: "com.acme.notes", name: "Notes", onDeviceWithUdid: udid,
                             applicationGroupsEntitlement: ["group.com.acme.notes.shared"])
        try fixture.writeAppGroup(identifier: "group.com.acme.notes.shared", onDeviceWithUdid: udid)

        let device = try #require(DeviceLoader(devicesDirectoryURL: fixture.url).loadDevice(withUdid: udid))
        let notes = try #require(device.apps.first)
        let target = try #require(AppSnapshotTarget(app: notes, device: device))
        // What the name rule resolved before: the same app, blind to the group.
        let nameRuleTarget = AppSnapshotTarget(bundleIdentifier: target.bundleIdentifier,
                                               appDisplayName: target.appDisplayName,
                                               appShortVersion: target.appShortVersion,
                                               appBuildVersion: target.appBuildVersion,
                                               deviceUDID: target.deviceUDID,
                                               deviceName: target.deviceName,
                                               osVersion: target.osVersion,
                                               dataContainerURL: target.dataContainerURL,
                                               appGroupContainers: [])
        let service = AppSnapshotService(store: AppSnapshotStore(rootURL: storeFixture.url),
                                         appActionService: MockSimulatorAppActionService())

        let snapshot = try await service.captureSnapshot(of: nameRuleTarget, label: "Name rule", includeCaches: false)
        let plan = try await service.prepareRestore(of: snapshot, to: target)

        #expect(plan.warnings == [.containerNotInSnapshot(.appGroup(identifier: "group.com.acme.notes.shared"))])
    }

    private static func group(_ identifier: String) -> AppGroup {
        AppGroup(identifier: identifier, uuid: UUID().uuidString, userDefaultsDomains: [])
    }

    private static func app(_ bundleIdentifier: String, groups: Set<String>?) -> SimulatoriOSApp {
        SimulatoriOSApp(displayName: bundleIdentifier,
                        bundleIdentifier: bundleIdentifier,
                        appDocumentsFolderURL: URL(fileURLWithPath: "/tmp/\(bundleIdentifier)"),
                        appPackageURL: nil,
                        hasWatchApp: false,
                        userDefaultsDomains: [],
                        applicationGroupIdentifiers: groups)
    }
}
