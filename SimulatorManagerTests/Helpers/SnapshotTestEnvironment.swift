import Foundation
@testable import SimulatorManager

/// A snapshot service wired entirely to throwaway directories: its own store root, an app data
/// container and one app group container, all under the temporary directory.
struct SnapshotTestEnvironment {
    static let bundleIdentifier = "com.acme.app"
    static let groupIdentifier = "group.com.acme.app"

    let storeFixture: SnapshotStoreFixtureDirectory
    let container: ContainerFixtureDirectory
    let groupContainer: ContainerFixtureDirectory
    let store: AppSnapshotStore
    let appActions: MockSimulatorAppActionService
    let service: AppSnapshotService
    let target: AppSnapshotTarget

    init(includeAppGroup: Bool = true) throws {
        storeFixture = try SnapshotStoreFixtureDirectory()
        container = try ContainerFixtureDirectory(name: "app-data")
        groupContainer = try ContainerFixtureDirectory(name: "app-group")

        try container.writeContainerMetadata(identifier: Self.bundleIdentifier)
        try container.write("hello", at: "Documents/note.txt")
        try container.write("state", at: "Library/Application Support/state.bin")
        try container.writeDefaults(["theme": "dark", "launchCount": 1], domain: Self.bundleIdentifier)
        try container.write("cached", at: "\(SimulatorPaths.cachesPath)/blob.bin")
        try container.write("scratch", at: "\(SimulatorPaths.temporaryPath)/scratch.txt")

        try groupContainer.writeContainerMetadata(identifier: Self.groupIdentifier)
        try groupContainer.write("shared", at: "shared.txt")
        try groupContainer.writeDefaults(["shared": true], domain: Self.groupIdentifier)

        store = AppSnapshotStore(rootURL: storeFixture.url)
        appActions = MockSimulatorAppActionService()
        service = AppSnapshotService(store: store, appActionService: appActions)
        target = AppSnapshotTarget(
            bundleIdentifier: Self.bundleIdentifier,
            appDisplayName: "Acme",
            appShortVersion: "1.2",
            appBuildVersion: "34",
            deviceUDID: "UDID-1",
            deviceName: "iPhone 17 Pro",
            osVersion: "iOS 26.1",
            dataContainerURL: container.url,
            appGroupContainers: includeAppGroup
                ? [AppGroupContainer(identifier: Self.groupIdentifier, url: groupContainer.url)]
                : []
        )
    }

    /// The same app, with whatever the test wants to differ from the captured state.
    func target(
        shortVersion: String? = "1.2",
        buildVersion: String? = "34",
        osVersion: String = "iOS 26.1",
        bundleIdentifier: String = SnapshotTestEnvironment.bundleIdentifier
    ) -> AppSnapshotTarget {
        AppSnapshotTarget(
            bundleIdentifier: bundleIdentifier,
            appDisplayName: target.appDisplayName,
            appShortVersion: shortVersion,
            appBuildVersion: buildVersion,
            deviceUDID: target.deviceUDID,
            deviceName: target.deviceName,
            osVersion: osVersion,
            dataContainerURL: target.dataContainerURL,
            appGroupContainers: target.appGroupContainers
        )
    }

    func remove() {
        storeFixture.remove()
        container.remove()
        groupContainer.remove()
    }
}
