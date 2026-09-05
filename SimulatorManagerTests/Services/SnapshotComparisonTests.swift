import Foundation
import Testing
@testable import SimulatorManager

@Suite("Snapshot diffing")
struct SnapshotComparisonTests {
    @Test("Reports added, removed and modified files with their sizes")
    func reportsFileChanges() async throws {
        let environment = try SnapshotTestEnvironment(includeAppGroup: false)

        defer {
            environment.remove()
        }

        let snapshot = try await environment.service.captureSnapshot(of: environment.target,
                                                                     label: "Baseline",
                                                                     includeCaches: false)

        try environment.container.write("hello there", at: "Documents/note.txt")
        try environment.container.write("brand new", at: "Documents/new.txt")
        try environment.container.removeItem(at: "Library/Application Support/state.bin")

        let diff = try await environment.service.diff(snapshot, againstLiveContainersOf: environment.target)
        let changes = try #require(diff.containerDiffs.first { $0.kind == .appData }).fileChanges

        let modified = try #require(changes.first { $0.relativePath == "Documents/note.txt" })
        #expect(modified.kind == .modified)
        #expect(modified.oldByteSize == 5)
        #expect(modified.newByteSize == 11)

        let added = try #require(changes.first { $0.relativePath == "Documents/new.txt" })
        #expect(added.kind == .added)
        #expect(added.newByteSize == 9)

        let removed = try #require(changes.first { $0.relativePath == "Library/Application Support/state.bin" })
        #expect(removed.kind == .removed)
        #expect(removed.oldByteSize == 5)
    }

    @Test("Treats a same-size file with different content as modified")
    func detectsSameSizeContentChange() async throws {
        let environment = try SnapshotTestEnvironment(includeAppGroup: false)

        defer {
            environment.remove()
        }

        let snapshot = try await environment.service.captureSnapshot(of: environment.target,
                                                                     label: "Baseline",
                                                                     includeCaches: false)
        try environment.container.write("world", at: "Documents/note.txt")

        let diff = try await environment.service.diff(snapshot, againstLiveContainersOf: environment.target)
        let changes = try #require(diff.containerDiffs.first { $0.kind == .appData }).fileChanges

        let modified = try #require(changes.first { $0.relativePath == "Documents/note.txt" })
        #expect(modified.kind == .modified)
        #expect(modified.oldByteSize == modified.newByteSize)
    }

    @Test("Does not report a file whose modification date moved but whose content did not")
    func ignoresModificationDates() async throws {
        let environment = try SnapshotTestEnvironment(includeAppGroup: false)

        defer {
            environment.remove()
        }

        let snapshot = try await environment.service.captureSnapshot(of: environment.target,
                                                                     label: "Baseline",
                                                                     includeCaches: false)

        let noteURL = environment.container.url.appendingPathComponent("Documents/note.txt")
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(3600)],
                                              ofItemAtPath: noteURL.path)

        let diff = try await environment.service.diff(snapshot, againstLiveContainersOf: environment.target)
        #expect(!diff.hasChanges)
    }

    @Test("Reports changed preferences per key rather than as one modified plist")
    func reportsDefaultsAtKeyGranularity() async throws {
        let environment = try SnapshotTestEnvironment(includeAppGroup: false)

        defer {
            environment.remove()
        }

        let snapshot = try await environment.service.captureSnapshot(of: environment.target,
                                                                     label: "Baseline",
                                                                     includeCaches: false)
        try environment.container.writeDefaults(["theme": "light", "sessionToken": "abc"],
                                                domain: SnapshotTestEnvironment.bundleIdentifier)

        let diff = try await environment.service.diff(snapshot, againstLiveContainersOf: environment.target)
        let containerDiff = try #require(diff.containerDiffs.first { $0.kind == .appData })

        // The plist itself must not surface as a file change; that is the whole point.
        #expect(!containerDiff.fileChanges
            .contains { $0.relativePath.hasPrefix(SimulatorPaths.userDefaultsPath) })

        let changed = try #require(containerDiff.defaultsChanges.first { $0.key == "theme" })
        #expect(changed.kind == .changed)
        #expect(changed.domain == SnapshotTestEnvironment.bundleIdentifier)
        #expect(changed.oldValue == "dark")
        #expect(changed.newValue == "light")

        let added = try #require(containerDiff.defaultsChanges.first { $0.key == "sessionToken" })
        #expect(added.kind == .added)

        let removed = try #require(containerDiff.defaultsChanges.first { $0.key == "launchCount" })
        #expect(removed.kind == .removed)
        #expect(removed.oldValue == "1")
    }

    @Test("Falls back to a file change when a preferences file is not a readable property list")
    func fallsBackForUnreadablePreferences() async throws {
        let environment = try SnapshotTestEnvironment(includeAppGroup: false)

        defer {
            environment.remove()
        }

        let snapshot = try await environment.service.captureSnapshot(of: environment.target,
                                                                     label: "Baseline",
                                                                     includeCaches: false)
        try environment.container.write("not a plist at all",
                                        at: "\(SimulatorPaths.userDefaultsPath)/\(SnapshotTestEnvironment.bundleIdentifier).plist")

        let diff = try await environment.service.diff(snapshot, againstLiveContainersOf: environment.target)
        let containerDiff = try #require(diff.containerDiffs.first { $0.kind == .appData })

        #expect(containerDiff.defaultsChanges.isEmpty)
        #expect(containerDiff.fileChanges
            .contains { $0.relativePath.hasPrefix(SimulatorPaths.userDefaultsPath) && $0.kind == .modified })
    }

    @Test("Ignores caches in the live container when the snapshot left them out")
    func appliesSnapshotExclusionsToLiveContainer() async throws {
        let environment = try SnapshotTestEnvironment(includeAppGroup: false)

        defer {
            environment.remove()
        }

        let snapshot = try await environment.service.captureSnapshot(of: environment.target,
                                                                     label: "Baseline",
                                                                     includeCaches: false)
        try environment.container.write("fresh", at: "\(SimulatorPaths.cachesPath)/another.bin")

        let diff = try await environment.service.diff(snapshot, againstLiveContainersOf: environment.target)
        #expect(!diff.hasChanges)
    }

    @Test("Compares two snapshots against each other")
    func comparesTwoSnapshots() async throws {
        let environment = try SnapshotTestEnvironment(includeAppGroup: false)

        defer {
            environment.remove()
        }

        let before = try await environment.service.captureSnapshot(of: environment.target,
                                                                   label: "Before",
                                                                   includeCaches: false)
        try environment.container.write("after", at: "Documents/note.txt")
        let after = try await environment.service.captureSnapshot(of: environment.target,
                                                                  label: "After",
                                                                  includeCaches: false)

        let diff = try await environment.service.diff(before, against: after)
        let containerDiff = try #require(diff.containerDiffs.first { $0.kind == .appData })

        #expect(containerDiff.fileChanges.contains { $0.relativePath == "Documents/note.txt" && $0.kind == .modified })
        #expect(diff.renderedText.contains("Documents/note.txt"))
    }

    @Test("Renders an unchanged comparison as text saying so")
    func rendersUnchangedDiff() async throws {
        let environment = try SnapshotTestEnvironment(includeAppGroup: false)

        defer {
            environment.remove()
        }

        let snapshot = try await environment.service.captureSnapshot(of: environment.target,
                                                                     label: "Baseline",
                                                                     includeCaches: false)
        let diff = try await environment.service.diff(snapshot, againstLiveContainersOf: environment.target)

        #expect(!diff.hasChanges)
        #expect(diff.renderedText.contains("No differences."))
    }
}
