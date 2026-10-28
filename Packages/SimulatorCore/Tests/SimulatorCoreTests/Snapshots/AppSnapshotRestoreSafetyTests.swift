import Foundation
import Testing
@testable import SimulatorCore

@Suite("App snapshot restore safety")
struct AppSnapshotRestoreSafetyTests {
    @Test("A restore that fails partway puts the previous data back and names the safety snapshot")
    func rollsBackFailedRestore() async throws {
        let environment = try SnapshotTestEnvironment()
        let snapshot = try await environment.service.captureSnapshot(of: environment.target,
                                                                     label: "Baseline",
                                                                     includeCaches: false)
        let appData = try #require(snapshot.manifest.containers.first { $0.kind == .appData })
        let unreadableURL = snapshot.payloadURL(for: appData).appendingPathComponent("Documents/note.txt")

        // An unreadable payload file makes the copy fail after the container was already emptied.
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadableURL.path)

        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unreadableURL.path)
            environment.remove()
        }

        try environment.container.write("edited", at: "Documents/note.txt")
        try environment.container.write("new", at: "Documents/added-later.txt")

        let plan = try await environment.service.prepareRestore(of: snapshot, to: environment.target)

        do {
            _ = try await environment.service.restore(plan)
            Issue.record("The restore should have failed")
        } catch let AppSnapshotError.restoreFailed(_, safetySnapshotID, rolledBack) {
            #expect(rolledBack)

            let listed = await environment.service.allSnapshots()
            #expect(listed.contains { $0.id == safetySnapshotID && $0.manifest.isSafetySnapshot })
        }

        #expect(environment.container.contents(at: "Documents/note.txt") == "edited")
        #expect(environment.container.contents(at: "Documents/added-later.txt") == "new")
        #expect(environment.container.contents(at: "Library/Application Support/state.bin") == "state")
    }

    @Test("Warns about an app group the target has but the snapshot never captured")
    func warnsAboutUncapturedAppGroup() async throws {
        let environment = try SnapshotTestEnvironment()

        defer {
            environment.remove()
        }

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
        let snapshot = try await environment.service.captureSnapshot(of: withoutGroup,
                                                                     label: "Before the group",
                                                                     includeCaches: false)

        let plan = try await environment.service.prepareRestore(of: snapshot, to: environment.target)

        #expect(plan.warnings == [.containerNotInSnapshot(.appGroup(identifier: SnapshotTestEnvironment.groupIdentifier))])
    }

    @Test("Keeps only the newest safety snapshots of an app")
    func prunesSafetySnapshots() async throws {
        let environment = try SnapshotTestEnvironment()

        defer {
            environment.remove()
        }

        let baseline = try await environment.service.captureSnapshot(of: environment.target,
                                                                     label: "Baseline",
                                                                     includeCaches: false)
        var safetySnapshotIDs: [String] = []

        for run in 1 ... AppSnapshotService.retainedSafetySnapshotCount + 2 {
            try environment.container.write("run \(run)", at: "Documents/note.txt")

            let plan = try await environment.service.prepareRestore(of: baseline, to: environment.target)
            try safetySnapshotIDs.append(await environment.service.restore(plan).id)
        }

        let listed = await environment.service.allSnapshots()
        let safetySnapshots = listed.filter(\.manifest.isSafetySnapshot)

        #expect(safetySnapshots.count == AppSnapshotService.retainedSafetySnapshotCount)
        #expect(Set(safetySnapshots.map(\.id)) == Set(safetySnapshotIDs.suffix(AppSnapshotService.retainedSafetySnapshotCount)))
        #expect(listed.contains { $0.id == baseline.id })
    }

    @Test("Never prunes a safety snapshot that was itself just restored")
    func keepsRestoredSafetySnapshot() async throws {
        let environment = try SnapshotTestEnvironment()

        defer {
            environment.remove()
        }

        let baseline = try await environment.service.captureSnapshot(of: environment.target,
                                                                     label: "Baseline",
                                                                     includeCaches: false)
        let firstPlan = try await environment.service.prepareRestore(of: baseline, to: environment.target)
        let oldest = try await environment.service.restore(firstPlan)

        // Leaves the oldest as the last one kept, so the undo point its own restore takes would push
        // it out.
        for _ in 1 ..< AppSnapshotService.retainedSafetySnapshotCount {
            let plan = try await environment.service.prepareRestore(of: baseline, to: environment.target)
            _ = try await environment.service.restore(plan)
        }

        let undoPlan = try await environment.service.prepareRestore(of: oldest, to: environment.target)
        _ = try await environment.service.restore(undoPlan)

        let listed = await environment.service.allSnapshots()
        #expect(listed.contains { $0.id == oldest.id })
    }

    @Test("Compares caches between two snapshots only when both captured them")
    func diffIgnoresCachesOneSideLeftOut() async throws {
        let environment = try SnapshotTestEnvironment()

        defer {
            environment.remove()
        }

        let withCaches = try await environment.service.captureSnapshot(of: environment.target,
                                                                       label: "With caches",
                                                                       includeCaches: true)
        let withoutCaches = try await environment.service.captureSnapshot(of: environment.target,
                                                                          label: "Without caches",
                                                                          includeCaches: false)

        let diff = try await environment.service.diff(withCaches, against: withoutCaches)

        #expect(!diff.hasChanges)
    }
}
