import Foundation
import Synchronization
import Testing
@testable import SimulatorCore

@Suite("Saving a snapshot to a folder")
struct AppSnapshotSaveServiceTests {
    static let expectedName = "iPhone-17-Pro_iOS-26.1_Acme_2026-10-20_12-30-05"

    @Test("Saves a complete, plainly named snapshot into the folder")
    func savesNamedSnapshot() async throws {
        let (environment, destination) = try Self.makeEnvironment()

        defer {
            environment.remove()
            destination.remove()
        }

        let savedURL = try await Self.makeService(environment)
            .saveSnapshot(of: environment.target, into: destination.url, contents: .everything, includeCaches: false, progress: nil)

        #expect(savedURL.lastPathComponent == Self.expectedName)
        #expect(savedURL.deletingLastPathComponent().standardizedFileURL == destination.url.standardizedFileURL)
        #expect(destination.exists("\(Self.expectedName)/\(AppSnapshotManifest.fileName)"))
        #expect(destination.contents(at: "\(Self.expectedName)/containers/app-data/Documents/note.txt") == "hello")
        #expect(destination.exists("\(Self.expectedName)/containers/app-group-0/shared.txt"))

        let manifest = try environment.store.readManifest(at: savedURL)
        #expect(manifest.label == Self.expectedName)
        #expect(manifest.bundleIdentifier == SnapshotTestEnvironment.bundleIdentifier)
    }

    @Test("Leaves nothing behind in the internal store")
    func movesOutOfStore() async throws {
        let (environment, destination) = try Self.makeEnvironment()

        defer {
            environment.remove()
            destination.remove()
        }

        _ = try await Self.makeService(environment)
            .saveSnapshot(of: environment.target, into: destination.url, contents: .everything, includeCaches: false, progress: nil)

        #expect(environment.store.allSnapshots().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: environment.storeFixture
                .url
                .appendingPathComponent(SnapshotTestEnvironment.bundleIdentifier)
                .path))
    }

    @Test("Honours the caches flag")
    func honoursCaches() async throws {
        let (environment, destination) = try Self.makeEnvironment()

        defer {
            environment.remove()
            destination.remove()
        }

        let savedURL = try await Self.makeService(environment)
            .saveSnapshot(of: environment.target, into: destination.url, contents: .everything, includeCaches: true, progress: nil)

        let cachedFile = savedURL.appendingPathComponent("containers/app-data/\(SimulatorPaths.cachesPath)/blob.bin")
        #expect(FileManager.default.fileExists(atPath: cachedFile.path))
    }

    @Test("Never overwrites a folder of the same name")
    func avoidsCollision() async throws {
        let (environment, destination) = try Self.makeEnvironment()

        defer {
            environment.remove()
            destination.remove()
        }

        try destination.write("keep me", at: "\(Self.expectedName)/existing.txt")

        let savedURL = try await Self.makeService(environment)
            .saveSnapshot(of: environment.target, into: destination.url, contents: .everything, includeCaches: false, progress: nil)

        #expect(savedURL.lastPathComponent == "\(Self.expectedName) 2")
        #expect(destination.contents(at: "\(Self.expectedName)/existing.txt") == "keep me")
        #expect(!destination.exists("\(Self.expectedName)/\(AppSnapshotManifest.fileName)"))
    }

    @Test("Refuses a folder that does not exist, before capturing anything")
    func missingDestination() async throws {
        let (environment, destination) = try Self.makeEnvironment()

        defer {
            environment.remove()
        }

        destination.remove()

        await #expect(throws: AppSnapshotSaveError.destinationMissing(path: destination.url.path)) {
            try await Self.makeService(environment)
                .saveSnapshot(of: environment.target, into: destination.url, contents: .everything, includeCaches: false, progress: nil)
        }
        #expect(environment.store.allSnapshots().isEmpty)
    }

    @Test("Refuses a folder that cannot be written to, before capturing anything")
    func unwritableDestination() async throws {
        let (environment, destination) = try Self.makeEnvironment()

        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: destination.url.path)

        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.url.path)
            environment.remove()
            destination.remove()
        }

        await #expect(throws: AppSnapshotSaveError.destinationNotWritable(path: destination.url.path)) {
            try await Self.makeService(environment)
                .saveSnapshot(of: environment.target, into: destination.url, contents: .everything, includeCaches: false, progress: nil)
        }
        #expect(environment.store.allSnapshots().isEmpty)
    }

    @Test("Reports capture progress as a fraction")
    func reportsProgress() async throws {
        let (environment, destination) = try Self.makeEnvironment()

        defer {
            environment.remove()
            destination.remove()
        }

        let fractions = Mutex<[Double]>([])

        _ = try await Self.makeService(environment)
            .saveSnapshot(of: environment.target, into: destination.url, contents: .everything, includeCaches: false) { fraction in
                fractions.withLock { $0.append(fraction) }
            }

        let reported = fractions.withLock { $0 }
        #expect(!reported.isEmpty)
        #expect(reported.allSatisfy { (0 ... 1).contains($0) })
    }
}

@Suite("Moving a snapshot out of the store")
struct AppSnapshotStoreMoveTests {
    @Test("Refuses an existing destination and leaves both sides untouched")
    func refusesExistingDestination() async throws {
        let environment = try SnapshotTestEnvironment()
        let destination = try ContainerFixtureDirectory(name: "occupied")

        defer {
            environment.remove()
            destination.remove()
        }

        try destination.write("keep me", at: "existing.txt")
        let snapshot = try await environment.service.captureSnapshot(of: environment.target,
                                                                     label: "Baseline",
                                                                     includeCaches: false)

        #expect(throws: CocoaError.self) {
            try environment.store.move(snapshot, to: destination.url)
        }
        #expect(destination.contents(at: "existing.txt") == "keep me")
        #expect(environment.store.allSnapshots().map(\.id) == [snapshot.id])
    }
}

private extension AppSnapshotSaveServiceTests {
    static func makeEnvironment() throws -> (SnapshotTestEnvironment, ContainerFixtureDirectory) {
        try (SnapshotTestEnvironment(), ContainerFixtureDirectory(name: "destination"))
    }

    static func makeService(_ environment: SnapshotTestEnvironment) -> AppSnapshotSaveService {
        AppSnapshotSaveService(snapshotService: environment.service,
                               timeZone: SnapshotExportNamingTests.utc,
                               now: { SnapshotExportNamingTests.date })
    }
}
