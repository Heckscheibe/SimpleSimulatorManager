import Foundation
import Testing
@testable import SimulatorCore

@Suite("Snapshot contents: restore and diff")
struct SnapshotContentsRestoreTests {
    static let storePath = "Library/Application Support/Model.sqlite"

    // MARK: - Restore

    @Test("A databases-only restore puts the database and its sidecars back and leaves documents alone")
    func restoresDatabasesOnly() async throws {
        let environment = try Self.makeEnvironmentWithStore()

        defer {
            environment.remove()
        }

        let container = environment.container
        let snapshot = try await Self.capture(environment, contents: .databases)

        try container.writeSQLiteDatabase(at: Self.storePath, rows: "changed")
        try container.write("changed wal", at: "\(Self.storePath)-wal")
        try container.removeItem(at: "\(Self.storePath)-shm")
        try container.write("changed", at: "Documents/note.txt")
        try container.write("written later", at: "Documents/later.txt")
        try container.writeSQLiteDatabase(at: "Documents/later.sqlite")

        _ = try await Self.restore(snapshot, in: environment)

        #expect(container.contents(at: Self.storePath)?.hasSuffix("rows") == true)
        #expect(container.contents(at: "\(Self.storePath)-wal") == "wal")
        #expect(container.contents(at: "\(Self.storePath)-shm") == "shm")
        #expect(container.contents(at: "Library/Application Support/.Model_SUPPORT/_EXTERNAL_DATA/A1B2") == "blob")
        // Outside the snapshot's contents: neither put back nor removed.
        #expect(container.contents(at: "Documents/note.txt") == "changed")
        #expect(container.contents(at: "Documents/later.txt") == "written later")
        // In scope but not in the snapshot: removed.
        #expect(!container.exists("Documents/later.sqlite"))
    }

    @Test("A databases-only restore leaves databases iOS created since alone")
    func restoreKeepsSystemDatabases() async throws {
        let environment = try Self.makeEnvironmentWithStore()

        defer {
            environment.remove()
        }

        let snapshot = try await Self.capture(environment, contents: .databases)
        try SnapshotContentsCaptureTests.writeSystemDatabases(in: environment.container)

        _ = try await Self.restore(snapshot, in: environment)

        #expect(environment.container.exists("Library/HTTPStorages/com.acme.app/httpstorages.sqlite"))
        #expect(environment.container.exists("Library/HTTPStorages/com.acme.app/httpstorages.sqlite-wal"))
        #expect(environment.container.exists("Library/Safari/PerSitePreferences.db"))
        #expect(environment.container.exists("Library/Application Support/.tipkit/tips-store.db"))
    }

    @Test("A stale live -wal the snapshot did not capture is removed with its database")
    func removesStaleWriteAheadLog() async throws {
        let environment = try SnapshotTestEnvironment(includeAppGroup: false)

        defer {
            environment.remove()
        }

        try environment.container.writeSQLiteDatabase(at: Self.storePath)
        let snapshot = try await Self.capture(environment, contents: .databases)

        try environment.container.write("stale", at: "\(Self.storePath)-wal")
        try environment.container.write("stale", at: "\(Self.storePath)-shm")
        try environment.container.removeItem(at: Self.storePath)

        _ = try await Self.restore(snapshot, in: environment)

        #expect(environment.container.exists(Self.storePath))
        #expect(!environment.container.exists("\(Self.storePath)-wal"))
        #expect(!environment.container.exists("\(Self.storePath)-shm"))
    }

    @Test("A database overwritten with something that is not one is still put back")
    func replacesUnrecognisedLiveFile() async throws {
        let environment = try SnapshotTestEnvironment(includeAppGroup: false)

        defer {
            environment.remove()
        }

        try environment.container.writeSQLiteDatabase(at: Self.storePath)
        let snapshot = try await Self.capture(environment, contents: .databases)
        try environment.container.write("corrupted", at: Self.storePath)

        _ = try await Self.restore(snapshot, in: environment)

        #expect(environment.container.contents(at: Self.storePath)?.hasSuffix("rows") == true)
    }

    @Test("The safety snapshot has the same contents, and restoring it undoes the restore")
    func safetySnapshotUndoes() async throws {
        let environment = try Self.makeEnvironmentWithStore()

        defer {
            environment.remove()
        }

        let container = environment.container
        let snapshot = try await Self.capture(environment, contents: .databases)

        try container.writeSQLiteDatabase(at: Self.storePath, rows: "newer")
        try container.writeSQLiteDatabase(at: "Documents/later.sqlite")
        try container.write("newer doc", at: "Documents/note.txt")

        let safety = try await Self.restore(snapshot, in: environment)

        #expect(safety.manifest.contents == .databases)
        #expect(safety.manifest.isSafetySnapshot)
        #expect(!container.exists("Documents/later.sqlite"))

        _ = try await Self.restore(safety, in: environment)

        #expect(container.contents(at: Self.storePath)?.hasSuffix("newer") == true)
        #expect(container.exists("Documents/later.sqlite"))
        #expect(container.contents(at: "Documents/note.txt") == "newer doc")
    }

    @Test("Restoring onto an app whose databases are all gone still works, and can be undone")
    func restoresOntoAppWithoutDatabases() async throws {
        let environment = try SnapshotTestEnvironment(includeAppGroup: false)

        defer {
            environment.remove()
        }

        try environment.container.writeSQLiteDatabase(at: Self.storePath)
        let snapshot = try await Self.capture(environment, contents: .databases)
        try environment.container.removeItem(at: Self.storePath)

        let safety = try await Self.restore(snapshot, in: environment)
        #expect(environment.container.exists(Self.storePath))

        _ = try await Self.restore(safety, in: environment)
        #expect(!environment.container.exists(Self.storePath))
    }

    @Test("Restoring a Realm removes its live .lock, .note and .management, and nothing else")
    func removesRealmAuxiliaryFiles() async throws {
        let environment = try SnapshotTestEnvironment(includeAppGroup: false)

        defer {
            environment.remove()
        }

        let container = environment.container
        try container.writeRealmDatabase(at: "Documents/default.realm")
        try container.writeRealmDatabase(at: "Other/other.realm")
        let snapshot = try await Self.capture(environment, contents: .databases)

        try container.writeRealmDatabase(at: "Documents/default.realm", objects: "changed")
        try container.write("lock", at: "Documents/default.realm.lock")
        try container.write("control", at: "Documents/default.realm.management/access_control.control.mx")
        try container.makeNamedPipe(at: "Documents/default.realm.note")
        try container.write("unrelated", at: "Documents/default.realm.backup.txt")
        try container.makeNamedPipe(at: "Documents/unrelated.pipe")

        _ = try await Self.restore(snapshot, in: environment)

        #expect(container.contents(at: "Documents/default.realm")?.hasSuffix("objects") == true)
        #expect(!container.exists("Documents/default.realm.lock"))
        #expect(!container.exists("Documents/default.realm.management"))
        #expect(!container.exists("Documents/default.realm.note"))
        #expect(container.contents(at: "Documents/default.realm.backup.txt") == "unrelated")
        #expect(container.isNamedPipe(at: "Documents/unrelated.pipe"))
        #expect(container.exists("Other/other.realm"))
        #expect(container.contents(at: "Documents/note.txt") == "hello")
    }

    @Test("A UserDefaults-only restore leaves documents and databases untouched")
    func restoresUserDefaultsOnly() async throws {
        let environment = try Self.makeEnvironmentWithStore()

        defer {
            environment.remove()
        }

        let container = environment.container
        let snapshot = try await Self.capture(environment, contents: .userDefaults)

        try container.writeDefaults(["theme": "light"], domain: SnapshotTestEnvironment.bundleIdentifier)
        try container.writeDefaults(["added": true], domain: "com.vendor.sdk")
        try environment.groupContainer.writeDefaults(["shared": false], domain: SnapshotTestEnvironment.groupIdentifier)
        try container.writeSQLiteDatabase(at: Self.storePath, rows: "changed")
        try container.write("changed", at: "Documents/note.txt")

        _ = try await Self.restore(snapshot, in: environment)

        #expect(container.defaults(domain: SnapshotTestEnvironment.bundleIdentifier)?["theme"] as? String == "dark")
        #expect(container.defaults(domain: "com.vendor.sdk") == nil)
        #expect(environment.groupContainer.defaults(domain: SnapshotTestEnvironment.groupIdentifier)?["shared"] as? Bool == true)
        #expect(container.contents(at: Self.storePath)?.hasSuffix("changed") == true)
        #expect(container.contents(at: "Documents/note.txt") == "changed")
    }

    // MARK: - Diff

    @Test("A live diff of a narrower snapshot reports nothing outside its contents")
    func liveDiffStaysInScope() async throws {
        let environment = try Self.makeEnvironmentWithStore()

        defer {
            environment.remove()
        }

        let snapshot = try await Self.capture(environment, contents: .databases)

        try environment.container.write("changed", at: "Documents/note.txt")
        try environment.container.write("new", at: "Documents/new.txt")
        try environment.container.writeDefaults(["theme": "light"], domain: SnapshotTestEnvironment.bundleIdentifier)

        let unchanged = try await environment.service.diff(snapshot, againstLiveContainersOf: environment.target)
        #expect(!unchanged.hasChanges)
        #expect(unchanged.comparedContents == .databases)

        try environment.container.writeSQLiteDatabase(at: Self.storePath, rows: "more rows")

        let changed = try await environment.service.diff(snapshot, againstLiveContainersOf: environment.target)
        let changes = changed.containerDiffs.flatMap(\.fileChanges)
        #expect(changes.map(\.relativePath) == [Self.storePath])
        #expect(changed.containerDiffs.allSatisfy { $0.defaultsChanges.isEmpty })
    }

    @Test("A diff between snapshots with different contents compares only what both hold, and says so")
    func snapshotDiffComparesCommonContents() async throws {
        let environment = try Self.makeEnvironmentWithStore()

        defer {
            environment.remove()
        }

        let everything = try await Self.capture(environment, contents: .everything)
        try environment.container.writeSQLiteDatabase(at: Self.storePath, rows: "more rows")
        try environment.container.write("changed", at: "Documents/note.txt")
        let databases = try await Self.capture(environment, contents: .databasesAndUserDefaults)
        let userDefaults = try await Self.capture(environment, contents: .userDefaults)

        let diff = try await environment.service.diff(everything, against: databases)

        #expect(diff.comparedContents == .databasesAndUserDefaults)
        #expect(diff.containerDiffs.flatMap(\.fileChanges).map(\.relativePath) == [Self.storePath])
        #expect(diff.renderedText.contains("Compared: database and UserDefaults"))

        // Nothing in common: refused rather than reported as unchanged.
        let databasesOnly = try await Self.capture(environment, contents: .databases)
        await #expect(throws: AppSnapshotError.nothingToCompare(.databases, .userDefaults)) {
            try await environment.service.diff(databasesOnly, against: userDefaults)
        }
    }

    @Test("A diff between two full snapshots renders exactly as before")
    func fullDiffHasNoComparedLine() async throws {
        let environment = try SnapshotTestEnvironment()

        defer {
            environment.remove()
        }

        let first = try await Self.capture(environment, contents: .everything)
        let second = try await Self.capture(environment, contents: .everything)

        let diff = try await environment.service.diff(first, against: second)

        #expect(diff.comparedContents == .everything)
        #expect(!diff.renderedText.contains("Compared:"))
    }

    // MARK: - Manifest

    @Test("Contents are written as words: an array of kinds, or \"everything\"")
    func encodesContents() throws {
        let encoder = JSONEncoder()
        let narrower = try String(data: encoder.encode(SnapshotContents.databasesAndUserDefaults), encoding: .utf8)
        let everything = try String(data: encoder.encode(SnapshotContents.everything), encoding: .utf8)
        let decoded = try JSONDecoder().decode(SnapshotContents.self, from: Data(#"["userDefaults"]"#.utf8))

        #expect(narrower == #"["databases","userDefaults"]"#)
        #expect(everything == #""everything""#)
        #expect(decoded == .userDefaults)
    }

    @Test("A manifest without contents decodes as everything, and restores and diffs as before")
    func legacyManifestIsEverything() async throws {
        let environment = try SnapshotTestEnvironment()

        defer {
            environment.remove()
        }

        let captured = try await Self.capture(environment, contents: .everything)
        try Self.removeContentsField(from: captured)

        let reloaded = try #require(await environment.service
            .snapshots(forBundleIdentifier: SnapshotTestEnvironment.bundleIdentifier)
            .first { $0.id == captured.id })
        #expect(reloaded.manifest.contents == .everything)

        try environment.container.write("changed", at: "Documents/note.txt")
        try environment.container.write("new", at: "Documents/added-later.txt")

        let diff = try await environment.service.diff(reloaded, againstLiveContainersOf: environment.target)
        #expect(Set(diff.containerDiffs.flatMap(\.fileChanges).map(\.relativePath))
            == ["Documents/note.txt", "Documents/added-later.txt"])

        _ = try await Self.restore(reloaded, in: environment)

        #expect(environment.container.contents(at: "Documents/note.txt") == "hello")
        #expect(!environment.container.exists("Documents/added-later.txt"))
    }
}

private extension SnapshotContentsRestoreTests {
    /// The standard fixture plus a Core Data store with its sidecars and external storage.
    static func makeEnvironmentWithStore() throws -> SnapshotTestEnvironment {
        let environment = try SnapshotTestEnvironment()
        try environment.container.writeSQLiteDatabase(at: storePath)
        try environment.container.write("wal", at: "\(storePath)-wal")
        try environment.container.write("shm", at: "\(storePath)-shm")
        try environment.container.write("blob", at: "Library/Application Support/.Model_SUPPORT/_EXTERNAL_DATA/A1B2")

        return environment
    }

    static func capture(_ environment: SnapshotTestEnvironment, contents: SnapshotContents) async throws -> AppSnapshot {
        try await SnapshotContentsCaptureTests.capture(environment, contents: contents)
    }

    /// - Returns: The safety snapshot.
    static func restore(_ snapshot: AppSnapshot, in environment: SnapshotTestEnvironment) async throws -> AppSnapshot {
        let plan = try await environment.service.prepareRestore(of: snapshot, to: environment.target)

        return try await environment.service.restore(plan)
    }

    /// Rewrites the manifest the way a snapshot taken before contents existed looks on disk.
    static func removeContentsField(from snapshot: AppSnapshot) throws {
        let manifestURL = snapshot.directoryURL.appendingPathComponent(AppSnapshotManifest.fileName)
        var json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        json["contents"] = nil
        try JSONSerialization.data(withJSONObject: json).write(to: manifestURL)
    }
}
