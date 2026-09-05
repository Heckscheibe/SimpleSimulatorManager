import Foundation
import Testing
@testable import SimulatorManager

@Suite("App snapshot restore")
struct AppSnapshotRestoreTests {
    @Test("Puts the container back exactly, and a diff afterwards reports no differences")
    func restoresCapturedState() async throws {
        let environment = try SnapshotTestEnvironment()

        defer {
            environment.remove()
        }

        let snapshot = try await environment.service.captureSnapshot(of: environment.target,
                                                                     label: "Baseline",
                                                                     includeCaches: false)

        try environment.container.write("changed", at: "Documents/note.txt")
        try environment.container.writeDefaults(["theme": "light"], domain: SnapshotTestEnvironment.bundleIdentifier)

        let plan = try await environment.service.prepareRestore(of: snapshot, to: environment.target)
        _ = try await environment.service.restore(plan)

        #expect(environment.container.contents(at: "Documents/note.txt") == "hello")
        #expect(environment.container.defaults(domain: SnapshotTestEnvironment.bundleIdentifier)?["theme"] as? String == "dark")

        let diff = try await environment.service.diff(snapshot, againstLiveContainersOf: environment.target)
        #expect(!diff.hasChanges)
    }

    @Test("Removes files written after the snapshot instead of only overwriting known ones")
    func removesFilesCreatedAfterTheSnapshot() async throws {
        let environment = try SnapshotTestEnvironment()

        defer {
            environment.remove()
        }

        let snapshot = try await environment.service.captureSnapshot(of: environment.target,
                                                                     label: "Baseline",
                                                                     includeCaches: false)
        try environment.container.write("new", at: "Documents/added-later.txt")

        let plan = try await environment.service.prepareRestore(of: snapshot, to: environment.target)
        _ = try await environment.service.restore(plan)

        #expect(!environment.container.exists("Documents/added-later.txt"))
    }

    @Test("Leaves the container metadata plist and the uncaptured caches alone")
    func preservesUncapturedPaths() async throws {
        let environment = try SnapshotTestEnvironment()

        defer {
            environment.remove()
        }

        let snapshot = try await environment.service.captureSnapshot(of: environment.target,
                                                                     label: "Baseline",
                                                                     includeCaches: false)
        try environment.container.write("newer cache", at: "\(SimulatorPaths.cachesPath)/blob.bin")

        let plan = try await environment.service.prepareRestore(of: snapshot, to: environment.target)
        _ = try await environment.service.restore(plan)

        #expect(environment.container.exists(MetaDataPlist.fileName))
        // There is no payload to put back, so wiping it would destroy regenerable data for nothing.
        #expect(environment.container.contents(at: "\(SimulatorPaths.cachesPath)/blob.bin") == "newer cache")
        #expect(environment.container.exists("\(SimulatorPaths.temporaryPath)/scratch.txt"))
    }

    @Test("Takes a safety snapshot of the live state, which is itself restorable")
    func takesRestorableSafetySnapshot() async throws {
        let environment = try SnapshotTestEnvironment()

        defer {
            environment.remove()
        }

        let baseline = try await environment.service.captureSnapshot(of: environment.target,
                                                                     label: "Baseline",
                                                                     includeCaches: false)
        try environment.container.write("edited", at: "Documents/note.txt")

        let plan = try await environment.service.prepareRestore(of: baseline, to: environment.target)
        let safetySnapshot = try await environment.service.restore(plan)

        #expect(safetySnapshot.manifest.isSafetySnapshot)
        #expect(environment.container.contents(at: "Documents/note.txt") == "hello")

        let undoPlan = try await environment.service.prepareRestore(of: safetySnapshot, to: environment.target)
        _ = try await environment.service.restore(undoPlan)

        #expect(environment.container.contents(at: "Documents/note.txt") == "edited")
    }

    @Test("Terminates the target app before overwriting its container")
    func terminatesTheAppFirst() async throws {
        let environment = try SnapshotTestEnvironment()

        defer {
            environment.remove()
        }

        let snapshot = try await environment.service.captureSnapshot(of: environment.target,
                                                                     label: "Baseline",
                                                                     includeCaches: false)
        let plan = try await environment.service.prepareRestore(of: snapshot, to: environment.target)
        _ = try await environment.service.restore(plan)

        #expect(environment.appActions.terminateCallCount == 1)
        #expect(environment.appActions.lastTerminatedApp?.bundleIdentifier == SnapshotTestEnvironment.bundleIdentifier)
        #expect(environment.appActions.lastTerminatedApp?.deviceUdid == "UDID-1")
    }

    @Test("Still restores when the app could not be terminated")
    func survivesTerminateFailure() async throws {
        let environment = try SnapshotTestEnvironment()

        defer {
            environment.remove()
        }

        let snapshot = try await environment.service.captureSnapshot(of: environment.target,
                                                                     label: "Baseline",
                                                                     includeCaches: false)
        try environment.container.write("edited", at: "Documents/note.txt")
        environment.appActions.setError(NSError(domain: "ShellCommand", code: 1))

        let plan = try await environment.service.prepareRestore(of: snapshot, to: environment.target)
        _ = try await environment.service.restore(plan)

        #expect(environment.container.contents(at: "Documents/note.txt") == "hello")
    }

    @Test("Refuses a restore onto a different bundle identifier and writes nothing")
    func refusesBundleIdentifierMismatch() async throws {
        let environment = try SnapshotTestEnvironment()

        defer {
            environment.remove()
        }

        let snapshot = try await environment.service.captureSnapshot(of: environment.target,
                                                                     label: "Baseline",
                                                                     includeCaches: false)
        try environment.container.write("edited", at: "Documents/note.txt")

        let otherApp = environment.target(bundleIdentifier: "com.acme.other")

        await #expect(throws: AppSnapshotError.bundleIdentifierMismatch(snapshot: SnapshotTestEnvironment.bundleIdentifier,
                                                                        target: "com.acme.other")) {
            try await environment.service.prepareRestore(of: snapshot, to: otherApp)
        }

        #expect(environment.container.contents(at: "Documents/note.txt") == "edited")
        #expect(environment.appActions.terminateCallCount == 0)
    }

    @Test("Warns rather than refuses when the app or OS version moved on")
    func warnsOnVersionMismatch() async throws {
        let environment = try SnapshotTestEnvironment()

        defer {
            environment.remove()
        }

        let snapshot = try await environment.service.captureSnapshot(of: environment.target,
                                                                     label: "Baseline",
                                                                     includeCaches: false)
        try environment.container.write("edited", at: "Documents/note.txt")

        let upgraded = environment.target(shortVersion: "2.0", buildVersion: "40", osVersion: "iOS 27.0")
        let plan = try await environment.service.prepareRestore(of: snapshot, to: upgraded)

        #expect(plan.hasWarnings)
        #expect(plan.warnings.contains(.appShortVersionMismatch(snapshot: "1.2", target: "2.0")))
        #expect(plan.warnings.contains(.appBuildVersionMismatch(snapshot: "34", target: "40")))
        #expect(plan.warnings.contains(.osVersionMismatch(snapshot: "iOS 26.1", target: "iOS 27.0")))

        _ = try await environment.service.restore(plan)
        #expect(environment.container.contents(at: "Documents/note.txt") == "hello")
    }

    @Test("A matching target produces no warnings at all")
    func reportsNoWarningsWhenNothingDiffers() async throws {
        let environment = try SnapshotTestEnvironment()

        defer {
            environment.remove()
        }

        let snapshot = try await environment.service.captureSnapshot(of: environment.target,
                                                                     label: "Baseline",
                                                                     includeCaches: false)
        let plan = try await environment.service.prepareRestore(of: snapshot, to: environment.target)

        #expect(plan.warnings.isEmpty)
    }

    @Test("Reports a snapshot with a missing payload before overwriting anything")
    func refusesIncompleteSnapshot() async throws {
        let environment = try SnapshotTestEnvironment()

        defer {
            environment.remove()
        }

        let snapshot = try await environment.service.captureSnapshot(of: environment.target,
                                                                     label: "Baseline",
                                                                     includeCaches: false)
        try environment.container.write("edited", at: "Documents/note.txt")

        let dataContainer = try #require(snapshot.manifest.containers.first { $0.kind == .appData })
        try FileManager.default.removeItem(at: snapshot.payloadURL(for: dataContainer))

        await #expect(throws: AppSnapshotError.missingPayload(containerName: SnapshotContainerKind.appData.displayName)) {
            try await environment.service.prepareRestore(of: snapshot, to: environment.target)
        }

        #expect(environment.container.contents(at: "Documents/note.txt") == "edited")
    }

    @Test("Skips, with a warning, an app group the target no longer has")
    func warnsAboutContainerMissingOnTarget() async throws {
        let environment = try SnapshotTestEnvironment()

        defer {
            environment.remove()
        }

        let snapshot = try await environment.service.captureSnapshot(of: environment.target,
                                                                     label: "Baseline",
                                                                     includeCaches: false)

        let withoutGroup = AppSnapshotTarget(
            bundleIdentifier: environment.target.bundleIdentifier,
            appDisplayName: environment.target.appDisplayName,
            appShortVersion: environment.target.appShortVersion,
            appBuildVersion: environment.target.appBuildVersion,
            deviceUDID: environment.target.deviceUDID,
            deviceName: environment.target.deviceName,
            osVersion: environment.target.osVersion,
            dataContainerURL: environment.target.dataContainerURL,
            appGroupContainers: []
        )

        let plan = try await environment.service.prepareRestore(of: snapshot, to: withoutGroup)
        #expect(plan.warnings
            .contains(.containerMissingOnTarget(.appGroup(identifier: SnapshotTestEnvironment.groupIdentifier))))

        _ = try await environment.service.restore(plan)
        #expect(environment.container.contents(at: "Documents/note.txt") == "hello")
    }

    @Test("Restores an app group container alongside the app's own")
    func restoresAppGroupContainer() async throws {
        let environment = try SnapshotTestEnvironment()

        defer {
            environment.remove()
        }

        let snapshot = try await environment.service.captureSnapshot(of: environment.target,
                                                                     label: "Baseline",
                                                                     includeCaches: false)
        try environment.groupContainer.write("edited", at: "shared.txt")

        let plan = try await environment.service.prepareRestore(of: snapshot, to: environment.target)
        _ = try await environment.service.restore(plan)

        #expect(environment.groupContainer.contents(at: "shared.txt") == "shared")
        #expect(environment.groupContainer.exists(MetaDataPlist.fileName))
    }

    @Test("Outlives the app being uninstalled and the device erased")
    func survivesContainerRemoval() async throws {
        let environment = try SnapshotTestEnvironment()

        defer {
            environment.remove()
        }

        let snapshot = try await environment.service.captureSnapshot(of: environment.target,
                                                                     label: "Baseline",
                                                                     includeCaches: false)

        // What an erase plus a reinstall leaves behind: the same container path, empty apart from
        // the metadata plist CoreSimulator writes for it.
        try FileManager.default.removeItem(at: environment.container.url)
        try FileManager.default.createDirectory(at: environment.container.url, withIntermediateDirectories: true)
        try environment.container.writeContainerMetadata(identifier: SnapshotTestEnvironment.bundleIdentifier)

        let listed = await environment.service
            .snapshots(forBundleIdentifier: SnapshotTestEnvironment.bundleIdentifier)
        try #require(listed.count == 1)

        let plan = try await environment.service.prepareRestore(of: listed[0], to: environment.target)
        _ = try await environment.service.restore(plan)

        #expect(environment.container.contents(at: "Documents/note.txt") == "hello")
        #expect(snapshot.id == listed[0].id)
    }
}
