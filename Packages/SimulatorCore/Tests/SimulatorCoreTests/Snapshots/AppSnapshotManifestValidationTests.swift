import Foundation
import Testing
@testable import SimulatorCore

/// A manifest is plain JSON that can travel with a snapshot saved to a folder, so the one field
/// that becomes a path — a container's payload directory name — is checked before it is used.
@Suite("Snapshot manifest validation")
struct AppSnapshotManifestValidationTests {
    @Test("A payload directory name that is not a single path component is refused when the manifest is read",
          arguments: ["../../../../outside", "/etc", "", ".", "..", "app-data/../../outside"])
    func refusesUnsafePayloadName(_ name: String) async throws {
        let environment = try SnapshotTestEnvironment(includeAppGroup: false)

        defer {
            environment.remove()
        }

        let snapshot = try await environment.service.captureSnapshot(of: environment.target,
                                                                     label: "Baseline",
                                                                     includeCaches: false)
        try Self.rewritePayloadDirectoryNames(of: snapshot, to: [name])

        #expect(throws: AppSnapshotError.unreadableManifest(snapshotID: snapshot.directoryURL.lastPathComponent)) {
            try environment.store.readManifest(at: snapshot.directoryURL)
        }
        #expect(await environment.service.snapshots(forBundleIdentifier: SnapshotTestEnvironment.bundleIdentifier).isEmpty)
        #expect(await environment.service.allSnapshots().isEmpty)
        #expect(await environment.service.snapshot(withID: snapshot.id) == nil)
    }

    @Test("Two containers sharing a payload directory name are refused")
    func refusesDuplicatePayloadNames() async throws {
        let environment = try SnapshotTestEnvironment()

        defer {
            environment.remove()
        }

        let snapshot = try await environment.service.captureSnapshot(of: environment.target,
                                                                     label: "Baseline",
                                                                     includeCaches: false)
        try #require(snapshot.manifest.containers.count == 2)
        try Self.rewritePayloadDirectoryNames(of: snapshot, to: ["app-data", "app-data"])

        #expect(throws: AppSnapshotError.unreadableManifest(snapshotID: snapshot.directoryURL.lastPathComponent)) {
            try environment.store.readManifest(at: snapshot.directoryURL)
        }
        #expect(await environment.service.allSnapshots().isEmpty)
    }

    @Test("A payload directory that is a symlink out of the snapshot cannot be restored or diffed")
    func refusesSymlinkedPayload() async throws {
        let environment = try SnapshotTestEnvironment(includeAppGroup: false)
        let outside = try ContainerFixtureDirectory(name: "outside")

        defer {
            environment.remove()
            outside.remove()
        }

        try outside.write("secret", at: "id_ed25519")
        let snapshot = try await environment.service.captureSnapshot(of: environment.target,
                                                                     label: "Baseline",
                                                                     includeCaches: false)
        let container = try #require(snapshot.manifest.containers.first)
        let payloadURL = snapshot.payloadURL(for: container)
        try FileManager.default.removeItem(at: payloadURL)
        try FileManager.default.createSymbolicLink(at: payloadURL, withDestinationURL: outside.url)

        // The manifest itself is valid, so the snapshot is still listed; it just cannot be restored.
        let listed = try #require(await environment.service.snapshot(withID: snapshot.id))

        await #expect(throws: AppSnapshotError.missingPayload(containerName: container.kind.displayName)) {
            try await environment.service.prepareRestore(of: listed, to: environment.target)
        }
        // A diff lists file names and sizes, so it must not walk the symlink either.
        await #expect(throws: AppSnapshotError.missingPayload(containerName: container.kind.displayName)) {
            try await environment.service.diff(listed, againstLiveContainersOf: environment.target)
        }
        await #expect(throws: AppSnapshotError.missingPayload(containerName: container.kind.displayName)) {
            try await environment.service.diff(listed, against: listed)
        }
    }

    @Test("A containers directory that is a symlink out of the snapshot cannot be restored")
    func refusesSymlinkedContainersDirectory() async throws {
        let environment = try SnapshotTestEnvironment(includeAppGroup: false)
        let outside = try ContainerFixtureDirectory(name: "outside")

        defer {
            environment.remove()
            outside.remove()
        }

        let snapshot = try await environment.service.captureSnapshot(of: environment.target,
                                                                     label: "Baseline",
                                                                     includeCaches: false)
        let container = try #require(snapshot.manifest.containers.first)
        let movedURL = outside.url.appendingPathComponent("moved", isDirectory: true)
        try FileManager.default.moveItem(at: snapshot.containersDirectoryURL, to: movedURL)
        try FileManager.default.createSymbolicLink(at: snapshot.containersDirectoryURL, withDestinationURL: movedURL)

        await #expect(throws: AppSnapshotError.missingPayload(containerName: container.kind.displayName)) {
            try await environment.service.prepareRestore(of: snapshot, to: environment.target)
        }
    }

    @Test("A normal manifest and one written before contents existed both still load")
    func loadsValidAndLegacyManifests() async throws {
        let environment = try SnapshotTestEnvironment()

        defer {
            environment.remove()
        }

        let snapshot = try await environment.service.captureSnapshot(of: environment.target,
                                                                     label: "Baseline",
                                                                     includeCaches: false)

        #expect(try environment.store.readManifest(at: snapshot.directoryURL) == snapshot.manifest)

        let manifestURL = snapshot.directoryURL.appendingPathComponent(AppSnapshotManifest.fileName)
        var json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        json["contents"] = nil
        try JSONSerialization.data(withJSONObject: json).write(to: manifestURL)

        let legacy = try environment.store.readManifest(at: snapshot.directoryURL)
        #expect(legacy.contents == .everything)
        #expect(legacy.containers == snapshot.manifest.containers)
        _ = try await environment.service.prepareRestore(of: AppSnapshot(manifest: legacy, directoryURL: snapshot.directoryURL),
                                                         to: environment.target)
    }

    @Test("The single-path-component rule", arguments: [
        ("app-data", true), ("app-group-0", true), ("group.com.acme.app", true), ("..hidden", true),
        ("", false), (".", false), ("..", false), ("a/b", false), ("/", false), ("../x", false)
    ])
    func singlePathComponent(_ name: String, _ expected: Bool) {
        #expect(SimulatorPaths.isSinglePathComponent(name) == expected)
    }
}

extension AppSnapshotManifestValidationTests {
    /// Rewrites each container's payload directory name in the manifest on disk, in order.
    static func rewritePayloadDirectoryNames(of snapshot: AppSnapshot, to names: [String]) throws {
        let manifestURL = snapshot.directoryURL.appendingPathComponent(AppSnapshotManifest.fileName)
        var json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        var containers = try #require(json["containers"] as? [[String: Any]])
        try #require(containers.count == names.count)

        for index in containers.indices {
            containers[index]["payloadDirectoryName"] = names[index]
        }

        json["containers"] = containers
        try JSONSerialization.data(withJSONObject: json).write(to: manifestURL)
    }
}
