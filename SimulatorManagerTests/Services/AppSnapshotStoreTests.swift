import Foundation
import Testing
@testable import SimulatorManager

@Suite("Snapshot storage")
struct AppSnapshotStoreTests {
    @Test("Lists an app's snapshots newest first")
    func listsNewestFirst() async throws {
        let environment = try SnapshotTestEnvironment(includeAppGroup: false)

        defer {
            environment.remove()
        }

        let older = try await environment.service.captureSnapshot(of: environment.target,
                                                                  label: "Older",
                                                                  includeCaches: false)
        let newer = try await environment.service.captureSnapshot(of: environment.target,
                                                                  label: "Newer",
                                                                  includeCaches: false)

        let snapshots = await environment.service
            .snapshots(forBundleIdentifier: SnapshotTestEnvironment.bundleIdentifier)

        try #require(snapshots.count == 2)
        #expect(snapshots[0].id == newer.id)
        #expect(snapshots[1].id == older.id)
    }

    @Test("Reports per-snapshot and total size across every app")
    func reportsSizes() async throws {
        let environment = try SnapshotTestEnvironment(includeAppGroup: false)

        defer {
            environment.remove()
        }

        let first = try await environment.service.captureSnapshot(of: environment.target,
                                                                  label: "One",
                                                                  includeCaches: false)
        let second = try await environment.service.captureSnapshot(of: environment.target,
                                                                   label: "Two",
                                                                   includeCaches: true)

        let total = await environment.service.totalSnapshotByteSize()

        #expect(first.manifest.totalByteSize > 0)
        // The second includes caches and tmp, so it must be the larger of the two.
        #expect(second.manifest.totalByteSize > first.manifest.totalByteSize)
        #expect(total == first.manifest.totalByteSize + second.manifest.totalByteSize)
    }

    @Test("Deleting removes the payload from disk and from the listing")
    func deletesSnapshot() async throws {
        let environment = try SnapshotTestEnvironment(includeAppGroup: false)

        defer {
            environment.remove()
        }

        let snapshot = try await environment.service.captureSnapshot(of: environment.target,
                                                                     label: "Baseline",
                                                                     includeCaches: false)
        try await environment.service.deleteSnapshot(snapshot)

        #expect(!FileManager.default.fileExists(atPath: snapshot.directoryURL.path))

        let remaining = await environment.service
            .snapshots(forBundleIdentifier: SnapshotTestEnvironment.bundleIdentifier)
        #expect(remaining.isEmpty)

        let total = await environment.service.totalSnapshotByteSize()
        #expect(total == 0)
    }

    @Test("Skips a snapshot whose manifest cannot be read rather than offering it")
    func skipsUnreadableSnapshot() async throws {
        let environment = try SnapshotTestEnvironment(includeAppGroup: false)

        defer {
            environment.remove()
        }

        let snapshot = try await environment.service.captureSnapshot(of: environment.target,
                                                                     label: "Baseline",
                                                                     includeCaches: false)
        try Data("not json".utf8)
            .write(to: snapshot.directoryURL.appendingPathComponent(AppSnapshotManifest.fileName))

        let snapshots = await environment.service
            .snapshots(forBundleIdentifier: SnapshotTestEnvironment.bundleIdentifier)
        #expect(snapshots.isEmpty)

        #expect(throws: AppSnapshotError.unreadableManifest(snapshotID: snapshot.id)) {
            try environment.store.readManifest(at: snapshot.directoryURL)
        }
    }

    @Test("Keeps one app's snapshots out of another's listing")
    func separatesAppsByBundleIdentifier() async throws {
        let environment = try SnapshotTestEnvironment(includeAppGroup: false)

        defer {
            environment.remove()
        }

        _ = try await environment.service.captureSnapshot(of: environment.target,
                                                          label: "Baseline",
                                                          includeCaches: false)

        let others = await environment.service.snapshots(forBundleIdentifier: "com.acme.other")
        let everything = await environment.service.allSnapshots()

        #expect(others.isEmpty)
        #expect(everything.count == 1)
    }
}
