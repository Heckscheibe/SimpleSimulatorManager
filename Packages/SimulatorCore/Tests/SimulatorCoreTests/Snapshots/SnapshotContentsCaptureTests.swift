import Foundation
import Testing
@testable import SimulatorCore

@Suite("Snapshot contents: capture")
struct SnapshotContentsCaptureTests {
    // MARK: - SQLite

    @Test("A Core Data store is captured with its -wal, -shm and external storage, and nothing else")
    func capturesCoreDataStore() async throws {
        let environment = try SnapshotTestEnvironment(includeAppGroup: false)

        defer {
            environment.remove()
        }

        let container = environment.container
        try container.writeSQLiteDatabase(at: "Library/Application Support/Model.sqlite")
        try container.write("wal", at: "Library/Application Support/Model.sqlite-wal")
        try container.write("shm", at: "Library/Application Support/Model.sqlite-shm")
        try container.write("blob", at: "Library/Application Support/.Model_SUPPORT/_EXTERNAL_DATA/A1B2")

        let snapshot = try await Self.capture(environment, contents: .databases)

        #expect(Self.payloadFiles(of: snapshot, kind: .appData) == [
            "Library/Application Support/Model.sqlite",
            "Library/Application Support/Model.sqlite-wal",
            "Library/Application Support/Model.sqlite-shm",
            "Library/Application Support/.Model_SUPPORT/_EXTERNAL_DATA/A1B2"
        ])
        #expect(snapshot.manifest.contents == .databases)
    }

    @Test("A SwiftData default.store and GRDB files are found by content, whatever their extension")
    func detectsByContent() async throws {
        let environment = try SnapshotTestEnvironment(includeAppGroup: false)

        defer {
            environment.remove()
        }

        try environment.container.writeSQLiteDatabase(at: "Library/Application Support/default.store")
        try environment.container.writeSQLiteDatabase(at: "Documents/app.db")
        try environment.container.writeSQLiteDatabase(at: "Documents/grdb")

        let snapshot = try await Self.capture(environment, contents: .databases)

        #expect(Self.payloadFiles(of: snapshot, kind: .appData) == [
            "Library/Application Support/default.store",
            "Documents/app.db",
            "Documents/grdb"
        ])
    }

    @Test("A file with a .sqlite extension that is not a database is not picked")
    func ignoresMisnamedFile() async throws {
        let environment = try SnapshotTestEnvironment(includeAppGroup: false)

        defer {
            environment.remove()
        }

        try environment.container.write("just text", at: "Documents/notes.sqlite")
        try environment.container.writeSQLiteDatabase(at: "Documents/real.sqlite")

        let snapshot = try await Self.capture(environment, contents: .databases)

        #expect(Self.payloadFiles(of: snapshot, kind: .appData) == ["Documents/real.sqlite"])
    }

    @Test("A database in an app group is captured from the group container")
    func capturesAppGroupDatabase() async throws {
        let environment = try SnapshotTestEnvironment()

        defer {
            environment.remove()
        }

        try environment.groupContainer.writeSQLiteDatabase(at: "Shared.sqlite")

        let snapshot = try await Self.capture(environment, contents: .databases)

        #expect(Self.payloadFiles(of: snapshot, kind: .appGroup(identifier: SnapshotTestEnvironment.groupIdentifier))
            == ["Shared.sqlite"])
        #expect(Self.payloadFiles(of: snapshot, kind: .appData).isEmpty)
    }

    @Test("A database under Library/Caches is captured only when caches are included")
    func cachesFlagAppliesToDatabases() async throws {
        let environment = try SnapshotTestEnvironment(includeAppGroup: false)

        defer {
            environment.remove()
        }

        try environment.container.writeSQLiteDatabase(at: "\(SimulatorPaths.cachesPath)/cache.sqlite")
        try environment.container.writeSQLiteDatabase(at: "Documents/main.sqlite")

        let withoutCaches = try await Self.capture(environment, contents: .databases, includeCaches: false)
        let withCaches = try await Self.capture(environment, contents: .databases, includeCaches: true)

        #expect(Self.payloadFiles(of: withoutCaches, kind: .appData) == ["Documents/main.sqlite"])
        #expect(Self.payloadFiles(of: withCaches, kind: .appData)
            == ["Documents/main.sqlite", "\(SimulatorPaths.cachesPath)/cache.sqlite"])
    }

    // MARK: - Realm

    @Test("A Realm is found by its header, with or without the .realm extension")
    func detectsRealmByHeader() async throws {
        let environment = try SnapshotTestEnvironment(includeAppGroup: false)

        defer {
            environment.remove()
        }

        try environment.container.writeRealmDatabase(at: "Documents/default.realm")
        try environment.container.writeRealmDatabase(at: "Documents/storage")

        let snapshot = try await Self.capture(environment, contents: .databases)

        #expect(Self.payloadFiles(of: snapshot, kind: .appData) == ["Documents/default.realm", "Documents/storage"])
    }

    @Test("An encrypted Realm, which has no readable header, is found by its extension")
    func detectsEncryptedRealm() async throws {
        let environment = try SnapshotTestEnvironment(includeAppGroup: false)

        defer {
            environment.remove()
        }

        try environment.container.writeEncryptedRealmDatabase(at: "Documents/secret.realm")
        try environment.container.writeEncryptedRealmDatabase(at: "Documents/secret.bin")

        let snapshot = try await Self.capture(environment, contents: .databases)

        #expect(Self.payloadFiles(of: snapshot, kind: .appData) == ["Documents/secret.realm"])
    }

    @Test("A Realm's .lock and .management are not captured, and its .note pipe fails neither option")
    func skipsRealmAuxiliaryFiles() async throws {
        let environment = try SnapshotTestEnvironment(includeAppGroup: false)

        defer {
            environment.remove()
        }

        try environment.container.writeRealmDatabase(at: "Documents/default.realm")
        try environment.container.write("lock", at: "Documents/default.realm.lock")
        try environment.container.write("control", at: "Documents/default.realm.management/access_control.control.mx")
        try environment.container.makeNamedPipe(at: "Documents/default.realm.note")

        let databases = try await Self.capture(environment, contents: .databases)
        let everything = try await Self.capture(environment, contents: .everything)

        #expect(Self.payloadFiles(of: databases, kind: .appData) == ["Documents/default.realm"])
        #expect(Self.payloadFiles(of: everything, kind: .appData).contains("Documents/default.realm"))
        #expect(!Self.payloadFiles(of: everything, kind: .appData).contains("Documents/default.realm.note"))
    }

    // MARK: - UserDefaults

    @Test("UserDefaults are the domain plists of both containers, own domain and SDK suites, and nothing else")
    func capturesUserDefaults() async throws {
        let environment = try SnapshotTestEnvironment()

        defer {
            environment.remove()
        }

        try environment.container.writeDefaults(["sdk": 1], domain: "com.vendor.sdk")
        try environment.container.write("not defaults", at: "\(SimulatorPaths.userDefaultsPath)/readme.txt")
        try environment.container.write("nested", at: "\(SimulatorPaths.userDefaultsPath)/ByHost/other.plist")
        try environment.container.writeSQLiteDatabase(at: "Library/Application Support/Model.sqlite")

        let snapshot = try await Self.capture(environment, contents: .userDefaults)

        #expect(Self.payloadFiles(of: snapshot, kind: .appData) == [
            "\(SimulatorPaths.userDefaultsPath)/\(SnapshotTestEnvironment.bundleIdentifier).plist",
            "\(SimulatorPaths.userDefaultsPath)/com.vendor.sdk.plist"
        ])
        #expect(Self.payloadFiles(of: snapshot, kind: .appGroup(identifier: SnapshotTestEnvironment.groupIdentifier))
            == ["\(SimulatorPaths.userDefaultsPath)/\(SnapshotTestEnvironment.groupIdentifier).plist"])
    }

    @Test("Databases and UserDefaults captures exactly the union of the two")
    func capturesUnion() async throws {
        let environment = try SnapshotTestEnvironment()

        defer {
            environment.remove()
        }

        try environment.container.writeSQLiteDatabase(at: "Library/Application Support/Model.sqlite")
        try environment.container.write("wal", at: "Library/Application Support/Model.sqlite-wal")
        try environment.groupContainer.writeRealmDatabase(at: "shared.realm")

        let databases = try await Self.capture(environment, contents: .databases)
        let userDefaults = try await Self.capture(environment, contents: .userDefaults)
        let both = try await Self.capture(environment, contents: .databasesAndUserDefaults)

        for kind in [SnapshotContainerKind.appData, .appGroup(identifier: SnapshotTestEnvironment.groupIdentifier)] {
            #expect(Self.payloadFiles(of: both, kind: kind)
                == Self.payloadFiles(of: databases, kind: kind).union(Self.payloadFiles(of: userDefaults, kind: kind)))
        }
    }

    // MARK: - Nothing found

    @Test("Databases only on an app without databases throws and leaves no snapshot behind")
    func refusesEmptyDatabasesSnapshot() async throws {
        let environment = try SnapshotTestEnvironment()

        defer {
            environment.remove()
        }

        await #expect(throws: AppSnapshotError.nothingInContents(.databases)) {
            try await Self.capture(environment, contents: .databases)
        }

        #expect(AppSnapshotError.nothingInContents(.databases).errorDescription
            == "This app has no database to snapshot.")
        #expect(await environment.service.snapshots(forBundleIdentifier: SnapshotTestEnvironment.bundleIdentifier).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: environment.storeFixture.url.path).isEmpty)
    }

    @Test("Databases iOS keeps in the container are not the app's, so they are left out")
    func skipsSystemDatabases() async throws {
        let environment = try SnapshotTestEnvironment(includeAppGroup: false)

        defer {
            environment.remove()
        }

        let container = environment.container
        try Self.writeSystemDatabases(in: container)

        await #expect(throws: AppSnapshotError.nothingInContents(.databases)) {
            try await Self.capture(environment, contents: .databases, includeCaches: true)
        }

        try container.writeSQLiteDatabase(at: "Library/Application Support/Model.sqlite")

        let snapshot = try await Self.capture(environment, contents: .databases, includeCaches: true)

        #expect(Self.payloadFiles(of: snapshot, kind: .appData) == ["Library/Application Support/Model.sqlite"])
    }

    @Test("An everything snapshot still holds iOS's databases")
    func everythingKeepsSystemDatabases() async throws {
        let environment = try SnapshotTestEnvironment(includeAppGroup: false)

        defer {
            environment.remove()
        }

        try environment.container.writeSQLiteDatabase(at: "Library/HTTPStorages/com.acme.app/httpstorages.sqlite")

        let snapshot = try await Self.capture(environment, contents: .everything)

        #expect(Self.payloadFiles(of: snapshot, kind: .appData).contains("Library/HTTPStorages/com.acme.app/httpstorages.sqlite"))
    }

    @Test("UserDefaults only on an app without defaults throws too")
    func refusesEmptyUserDefaultsSnapshot() async throws {
        let environment = try SnapshotTestEnvironment(includeAppGroup: false)

        defer {
            environment.remove()
        }

        try environment.container.removeItem(at: SimulatorPaths.userDefaultsPath)

        await #expect(throws: AppSnapshotError.nothingInContents(.userDefaults)) {
            try await Self.capture(environment, contents: .userDefaults)
        }
        #expect(AppSnapshotError.nothingInContents(.userDefaults).errorDescription
            == "This app has no UserDefaults to snapshot.")
    }

    @Test("Saving an option that finds nothing leaves the destination folder empty")
    func saveLeavesNothingInDestination() async throws {
        let environment = try SnapshotTestEnvironment()
        let destination = try ContainerFixtureDirectory(name: "destination")

        defer {
            environment.remove()
            destination.remove()
        }

        let service = AppSnapshotSaveService(snapshotService: environment.service)

        await #expect(throws: AppSnapshotError.nothingInContents(.databases)) {
            try await service.saveSnapshot(of: environment.target,
                                           into: destination.url,
                                           contents: .databases,
                                           includeCaches: false,
                                           progress: nil)
        }

        #expect(try FileManager.default.contentsOfDirectory(atPath: destination.url.path).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: environment.storeFixture.url.path).isEmpty)
    }

    @Test("A saved snapshot's label says what it holds; its folder name does not change")
    func labelNamesContents() async throws {
        let environment = try SnapshotTestEnvironment(includeAppGroup: false)
        let destination = try ContainerFixtureDirectory(name: "destination")

        defer {
            environment.remove()
            destination.remove()
        }

        try environment.container.writeSQLiteDatabase(at: "Documents/app.db")

        let service = AppSnapshotSaveService(snapshotService: environment.service,
                                             timeZone: SnapshotExportNamingTests.utc,
                                             now: { SnapshotExportNamingTests.date })
        let savedURL = try await service.saveSnapshot(of: environment.target,
                                                      into: destination.url,
                                                      contents: .databases,
                                                      includeCaches: false,
                                                      progress: nil)
        let manifest = try environment.store.readManifest(at: savedURL)
        let json = try JSONSerialization.jsonObject(
            with: Data(contentsOf: savedURL.appendingPathComponent(AppSnapshotManifest.fileName))
        ) as? [String: Any]

        #expect(savedURL.lastPathComponent == AppSnapshotSaveServiceTests.expectedName)
        #expect(manifest.label == "\(AppSnapshotSaveServiceTests.expectedName) (Database)")
        #expect(manifest.contents == .databases)
        #expect(json?["contents"] as? [String] == ["databases"])
    }

    @Test("Labels for each set of contents")
    func labelSuffixes() {
        #expect(SnapshotContents.everything.labelSuffix.isEmpty)
        #expect(SnapshotContents.databases.labelSuffix == " (Database)")
        #expect(SnapshotContents.userDefaults.labelSuffix == " (UserDefaults)")
        #expect(SnapshotContents.databasesAndUserDefaults.labelSuffix == " (Database and UserDefaults)")
    }
}

extension SnapshotContentsCaptureTests {
    /// What URLSession, URLCache, WebKit, Safari view controllers and TipKit write on their own.
    @discardableResult
    static func writeSystemDatabases(in container: ContainerFixtureDirectory) throws {
        try container.writeSQLiteDatabase(at: "Library/HTTPStorages/com.acme.app/httpstorages.sqlite")
        try container.write("wal", at: "Library/HTTPStorages/com.acme.app/httpstorages.sqlite-wal")
        try container.writeSQLiteDatabase(at: "\(SimulatorPaths.cachesPath)/com.acme.app/Cache.db")
        try container.writeSQLiteDatabase(at: "Library/WebKit/WebsiteData/Default/salt/IndexedDB/db.sqlite3")
        try container.writeSQLiteDatabase(at: "Library/Safari/PerSitePreferences.db")
        try container.writeSQLiteDatabase(at: "Library/Application Support/.tipkit/tips-store.db")
    }

    static func capture(
        _ environment: SnapshotTestEnvironment,
        contents: SnapshotContents,
        includeCaches: Bool = false
    ) async throws -> AppSnapshot {
        try await environment.service.captureSnapshot(of: environment.target,
                                                      label: "Baseline",
                                                      contents: contents,
                                                      includeCaches: includeCaches)
    }

    /// Every file in one container's payload, so a test asserts on all of it rather than on the
    /// paths it thought to check.
    static func payloadFiles(of snapshot: AppSnapshot, kind: SnapshotContainerKind) -> Set<String> {
        guard let container = snapshot.manifest.containers.first(where: { $0.kind == kind }) else {
            return []
        }

        return Set(SnapshotContainerFiles
            .fileSizesByRelativePath(in: snapshot.payloadURL(for: container), scope: .everything(includeCaches: true))
            .keys)
    }
}
