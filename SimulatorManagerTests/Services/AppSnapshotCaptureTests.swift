import Foundation
import Testing
@testable import SimulatorManager

@Suite("App snapshot capture")
struct AppSnapshotCaptureTests {
    @Test("Captures the app data container and every associated app group")
    func capturesEveryContainer() async throws {
        let environment = try SnapshotTestEnvironment()

        defer {
            environment.remove()
        }

        let snapshot = try await environment.service.captureSnapshot(of: environment.target,
                                                                     label: "Baseline",
                                                                     includeCaches: false)

        try #require(snapshot.manifest.containers.count == 2)
        #expect(snapshot.manifest.containers.contains { $0.kind == .appData })
        #expect(snapshot.manifest
            .containers
            .contains { $0.kind == .appGroup(identifier: SnapshotTestEnvironment.groupIdentifier) })

        let dataContainer = try #require(snapshot.manifest.containers.first { $0.kind == .appData })
        let payload = snapshot.payloadURL(for: dataContainer)
        #expect(FileManager.default.fileExists(atPath: payload.appendingPathComponent("Documents/note.txt").path))
    }

    @Test("Leaves caches and tmp out by default and includes them when asked")
    func honoursCachesFlag() async throws {
        let environment = try SnapshotTestEnvironment()

        defer {
            environment.remove()
        }

        let excluding = try await environment.service.captureSnapshot(of: environment.target,
                                                                      label: "Without caches",
                                                                      includeCaches: false)
        let including = try await environment.service.captureSnapshot(of: environment.target,
                                                                      label: "With caches",
                                                                      includeCaches: true)

        #expect(!Self.payloadContains("\(SimulatorPaths.cachesPath)/blob.bin", in: excluding))
        #expect(!Self.payloadContains("\(SimulatorPaths.temporaryPath)/scratch.txt", in: excluding))
        #expect(Self.payloadContains("\(SimulatorPaths.cachesPath)/blob.bin", in: including))
        #expect(Self.payloadContains("\(SimulatorPaths.temporaryPath)/scratch.txt", in: including))
        #expect(!excluding.manifest.includesCaches)
        #expect(including.manifest.includesCaches)
    }

    @Test("Never captures the container's own metadata plist")
    func excludesContainerMetadata() async throws {
        let environment = try SnapshotTestEnvironment()

        defer {
            environment.remove()
        }

        let snapshot = try await environment.service.captureSnapshot(of: environment.target,
                                                                     label: "Baseline",
                                                                     includeCaches: true)

        #expect(!Self.payloadContains(MetaDataPlist.fileName, in: snapshot))
    }

    @Test("Records the app, device and size in a manifest that reads back unchanged")
    func writesManifest() async throws {
        let environment = try SnapshotTestEnvironment()

        defer {
            environment.remove()
        }

        let snapshot = try await environment.service.captureSnapshot(of: environment.target,
                                                                     label: "Baseline",
                                                                     includeCaches: false)
        let manifest = snapshot.manifest

        #expect(manifest.bundleIdentifier == SnapshotTestEnvironment.bundleIdentifier)
        #expect(manifest.appDisplayName == "Acme")
        #expect(manifest.appShortVersion == "1.2")
        #expect(manifest.appBuildVersion == "34")
        #expect(manifest.deviceUDID == "UDID-1")
        #expect(manifest.deviceName == "iPhone 17 Pro")
        #expect(manifest.osVersion == "iOS 26.1")
        #expect(manifest.label == "Baseline")
        #expect(manifest.totalByteSize > 0)
        #expect(!manifest.isSafetySnapshot)

        let reloaded = try environment.store.readManifest(at: snapshot.directoryURL)
        #expect(reloaded == manifest)
    }

    @Test("Reports an app whose container is gone rather than writing an empty snapshot")
    func refusesToCaptureNothing() async throws {
        let environment = try SnapshotTestEnvironment(includeAppGroup: false)

        defer {
            environment.remove()
        }

        environment.container.remove()

        await #expect(throws: AppSnapshotError.nothingToCapture) {
            try await environment.service.captureSnapshot(of: environment.target,
                                                          label: "Doomed",
                                                          includeCaches: false)
        }

        let snapshots = await environment.service
            .snapshots(forBundleIdentifier: SnapshotTestEnvironment.bundleIdentifier)
        #expect(snapshots.isEmpty)
    }

    @Test("Reports progress while copying")
    func reportsProgress() async throws {
        let environment = try SnapshotTestEnvironment()

        defer {
            environment.remove()
        }

        let recorder = ProgressRecorder()
        _ = try await environment.service.captureSnapshot(of: environment.target,
                                                          label: "Baseline",
                                                          includeCaches: false,
                                                          progress: { recorder.record($0) })

        let updates = recorder.updates
        try #require(!updates.isEmpty)
        #expect(updates.allSatisfy { $0.totalByteCount > 0 })
        #expect(updates.last?.copiedByteCount ?? 0 > 0)
    }

    private static func payloadContains(_ relativePath: String, in snapshot: AppSnapshot) -> Bool {
        snapshot.manifest.containers.contains { container in
            FileManager.default.fileExists(
                atPath: snapshot.payloadURL(for: container).appendingPathComponent(relativePath).path
            )
        }
    }
}

/// Progress arrives from the service's work queue, so collecting it needs its own lock.
final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [SnapshotProgress] = []

    var updates: [SnapshotProgress] {
        lock.withLock { recorded }
    }

    func record(_ progress: SnapshotProgress) {
        lock.withLock { recorded.append(progress) }
    }
}
