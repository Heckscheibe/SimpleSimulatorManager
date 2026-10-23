import Foundation
import MCP
@testable import SimulatorMCPServer
import Testing

@Suite("Snapshot tools")
struct SnapshotToolTests {
    private let fixture: SnapshotToolFixture

    init() throws {
        fixture = try SnapshotToolFixture()
    }

    private var captureArguments: [String: Value] {
        ["bundle_id": .string(Sample.appBundleId), "udid": .string(Sample.iPhoneUdid)]
    }

    // MARK: - Capture

    @Test("Capture terminates the app first by default and reports it")
    func captureTerminatesByDefault() async throws {
        defer { fixture.remove() }

        let json = try await fixture.registry().json("capture_snapshot", captureArguments)
        let snapshot = try #require(json["snapshot"] as? [String: Any])

        #expect(json["appTermination"] as? String == "terminated")
        #expect((json["warnings"] as? [String])?.isEmpty == true)
        #expect(fixture.appActions.terminateCallCount == 1)
        #expect(fixture.appActions.lastTerminatedApp?.deviceUdid == Sample.iPhoneUdid)
        #expect(snapshot["bundleIdentifier"] as? String == Sample.appBundleId)
        #expect(snapshot["deviceUdid"] as? String == Sample.iPhoneUdid)
        #expect(snapshot["contents"] as? String == "everything")
        #expect(snapshot["containers"] as? [String] == ["appData", Sample.appGroupId])
        #expect((snapshot["label"] as? String)?.hasPrefix("iPhone-16-Pro_") == true)
    }

    @Test("terminate_app: false leaves the app running and warns about it")
    func captureWithoutTerminating() async throws {
        defer { fixture.remove() }

        var arguments = captureArguments
        arguments["terminate_app"] = false
        let json = try await fixture.registry().json("capture_snapshot", arguments)

        #expect(json["appTermination"] as? String == "notRequested")
        #expect((json["warnings"] as? [String])?.first?.contains("mid-write") == true)
        #expect(fixture.appActions.terminateCallCount == 0)
    }

    @Test("contents: databases captures the database with its -wal and labels it")
    func captureDatabasesOnly() async throws {
        defer { fixture.remove() }

        var arguments = captureArguments
        arguments["contents"] = "databases"
        arguments["label"] = "Before migration"
        let snapshot = try #require(try await fixture.registry().json("capture_snapshot", arguments)["snapshot"] as? [String: Any])

        #expect(snapshot["contents"] as? String == "databases")
        #expect(snapshot["label"] as? String == "Before migration")
        #expect(snapshot["containers"] as? [String] == ["appData", Sample.appGroupId])
    }

    @Test("The capture tool and its terminate_app argument both say the app is terminated")
    func descriptionsMentionTermination() throws {
        let tool = try #require(fixture.registry().tools.first { $0.name == "capture_snapshot" })
        let terminateApp = tool.inputSchema.objectValue?["properties"]?.objectValue?["terminate_app"]?.objectValue

        defer { fixture.remove() }

        #expect(tool.description?.contains("Terminates the app") == true)
        #expect(terminateApp?["description"]?.stringValue?.contains("Terminate the app") == true)
    }

    @Test("The server instructions and the snapshot tools say they are for migration testing")
    func descriptionsNameMigrationTesting() {
        let tools = fixture.registry().tools.filter { ["capture_snapshot", "diff_snapshot", "restore_snapshot"].contains($0.name) }

        defer { fixture.remove() }

        #expect(SimulatorMCPServer.instructions.contains("database migration"))
        #expect(SimulatorMCPServer.instructions.contains("downgrade"))
        #expect(tools.count == 3)
        for tool in tools {
            #expect(tool.description?.contains("migration") == true, "\(tool.name)")
        }
    }

    // MARK: - Listing and deleting

    @Test("list_snapshots lists newest first and filters by app; delete_snapshot removes one")
    func listAndDelete() async throws {
        defer { fixture.remove() }

        let registry = fixture.registry()
        let first = try await captureId(registry)
        let second = try await captureId(registry)

        let all = try #require(try await registry.json("list_snapshots", [:])["snapshots"] as? [[String: Any]])
        let otherApp: [String: Value] = ["bundle_id": .string(Sample.otherAppBundleId)]
        let other = try #require(try await registry.json("list_snapshots", otherApp)["snapshots"] as? [[String: Any]])

        #expect(all.compactMap { $0["id"] as? String } == [second, first])
        #expect(other.isEmpty)

        let deleted = try await registry.json("delete_snapshot", ["snapshot_id": .string(first)])

        #expect((deleted["deleted"] as? [String: Any])?["id"] as? String == first)
        #expect(fixture.storedSnapshotCount() == 1)
    }

    @Test("list_snapshots needs no flag")
    func listIsUngated() async {
        defer { fixture.remove() }

        #expect(await !fixture.registry(ServerOptions()).call("list_snapshots", arguments: nil).failed)
    }

    // MARK: - Diff

    @Test("A live diff reports a changed database; without --allow-user-defaults no defaults values appear")
    func liveDiffWithoutValues() async throws {
        defer { fixture.remove() }

        let registry = fixture.registry()
        let id = try await captureId(registry)
        try fixture.write(Data("SQLite format 3\0".utf8) + Data("v2 rows, migrated".utf8), at: "Library/Application Support/Model.sqlite")
        try fixture.write(PropertyListSerialization.data(fromPropertyList: ["token": "SECRET-VALUE", "launchCount": 4], format: .xml, options: 0),
                          at: "Library/Preferences/\(Sample.appBundleId).plist")

        let result = await registry.call("diff_snapshot", arguments: ["snapshot_id": .string(id), "against_live": true])
        let json = try result.json()
        let summary = try #require(json["summary"] as? [String: Any])
        let files = (json["containers"] as? [[String: Any]])?.flatMap { $0["files"] as? [[String: Any]] ?? [] } ?? []

        #expect(json["hasChanges"] as? Bool == true)
        #expect(json["againstLiveUdid"] as? String == Sample.iPhoneUdid)
        #expect(files.compactMap { $0["path"] as? String } == ["Library/Application Support/Model.sqlite"])
        #expect(summary["userDefaultsChanges"] as? Int == 2)
        #expect(!result.text.contains("SECRET-VALUE"))
        #expect(!result.text.contains("\"newValue\""))
        #expect((json["userDefaultsValuesNote"] as? String)?.contains("--allow-user-defaults") == true)
    }

    @Test("With --allow-user-defaults as well, the diff includes defaults values")
    func liveDiffWithValues() async throws {
        defer { fixture.remove() }

        let registry = fixture.registry(ServerOptions(allowUserDefaults: true, allowSnapshots: true))
        let id = try await captureId(registry)
        try fixture.write(PropertyListSerialization.data(fromPropertyList: ["token": "abc", "launchCount": 4], format: .xml, options: 0),
                          at: "Library/Preferences/\(Sample.appBundleId).plist")

        let json = try await registry.json("diff_snapshot", ["snapshot_id": .string(id), "against_live": true])
        let defaults = (json["containers"] as? [[String: Any]])?.flatMap { $0["userDefaults"] as? [[String: Any]] ?? [] } ?? []

        #expect(defaults.first?["key"] as? String == "launchCount")
        #expect(defaults.first?["oldValue"] as? String == "3")
        #expect(defaults.first?["newValue"] as? String == "4")
        #expect(json["userDefaultsValuesNote"] == nil)
    }

    @Test("More file changes than limit are cut, flagged and still counted")
    func diffTruncates() async throws {
        defer { fixture.remove() }

        let registry = fixture.registry()
        let id = try await captureId(registry)

        for index in 0 ..< 5 {
            try fixture.write("new", at: "Documents/added-\(index).txt")
        }

        let json = try await registry.json("diff_snapshot", ["snapshot_id": .string(id), "against_live": true, "limit": 2])
        let files = (json["containers"] as? [[String: Any]])?.flatMap { $0["files"] as? [[String: Any]] ?? [] } ?? []

        #expect(json["truncated"] as? Bool == true)
        #expect((json["summary"] as? [String: Any])?["filesAdded"] as? Int == 5)
        #expect(files.compactMap { $0["path"] as? String } == ["Documents/added-0.txt", "Documents/added-1.txt"])
    }

    @Test("A diff between two snapshots says what it compared")
    func diffBetweenSnapshots() async throws {
        defer { fixture.remove() }

        let registry = fixture.registry()
        let everything = try await captureId(registry)
        try fixture.write("changed", at: "Documents/note.txt")
        let databases = try await captureId(registry, contents: "databases")

        let json = try await registry.json("diff_snapshot", ["snapshot_id": .string(everything), "against_snapshot_id": .string(databases)])

        #expect(json["comparedContents"] as? String == "databases")
        #expect(json["againstSnapshotId"] as? String == databases)
        #expect(json["hasChanges"] as? Bool == false)
    }

    // MARK: - Restore

    @Test("Restore puts the captured state back and returns a safety snapshot that undoes it")
    func restoreAndUndo() async throws {
        defer { fixture.remove() }

        let registry = fixture.registry()
        let id = try await captureId(registry)
        try fixture.write("changed", at: "Documents/note.txt")

        let restore = try await registry.json("restore_snapshot", ["snapshot_id": .string(id)])
        let safetyId = try #require(restore["safetySnapshotId"] as? String)

        #expect(restore["restored"] as? Bool == true)
        #expect(fixture.contents(at: "Documents/note.txt") == "hello")

        _ = try await registry.json("restore_snapshot", ["snapshot_id": .string(safetyId)])

        #expect(fixture.contents(at: "Documents/note.txt") == "changed")
    }

    @Test("A version mismatch writes nothing without accept_warnings, and restores with it")
    func restoreNeedsAcceptedWarnings() async throws {
        defer { fixture.remove() }

        let registry = fixture.registry()
        let id = try await captureId(registry, contents: "databases")
        try fixture.setInstalledVersion("2.0")
        try fixture.write(Data("SQLite format 3\0".utf8) + Data("v2 rows".utf8), at: "Library/Application Support/Model.sqlite")
        let storedBefore = fixture.storedSnapshotCount()

        let refused = try await registry.json("restore_snapshot", ["snapshot_id": .string(id)])

        #expect(refused["restored"] as? Bool == false)
        #expect((refused["warnings"] as? [String])?.first?.contains("App version differs") == true)
        #expect(refused["safetySnapshotId"] == nil)
        #expect(fixture.contents(at: "Library/Application Support/Model.sqlite")?.hasSuffix("v2 rows") == true)
        #expect(fixture.storedSnapshotCount() == storedBefore)

        let accepted = try await registry.json("restore_snapshot", ["snapshot_id": .string(id), "accept_warnings": true])

        #expect(accepted["restored"] as? Bool == true)
        #expect(fixture.contents(at: "Library/Application Support/Model.sqlite")?.hasSuffix("v1 rows") == true)
        #expect(fixture.contents(at: "Library/Application Support/Model.sqlite-wal") == "wal")
    }

    // MARK: - Arguments

    struct BadCall: Sendable, CustomTestStringConvertible {
        let tool: String
        let arguments: [String: Value]
        let message: String

        var testDescription: String {
            "\(tool): \(message)"
        }
    }

    static let capture: [String: Value] = ["bundle_id": .string(Sample.appBundleId), "udid": .string(Sample.iPhoneUdid)]

    static let badCalls: [BadCall] = [
        BadCall(tool: "diff_snapshot", arguments: ["snapshot_id": "nope", "against_live": true], message: "No snapshot with id nope"),
        BadCall(tool: "restore_snapshot", arguments: ["snapshot_id": "nope"], message: "No snapshot with id nope"),
        BadCall(tool: "delete_snapshot", arguments: ["snapshot_id": "nope"], message: "No snapshot with id nope"),
        BadCall(tool: "capture_snapshot",
                arguments: ["bundle_id": .string(Sample.appBundleId), "udid": .string(Sample.unknownUdid)],
                message: "No simulator with UDID"),
        BadCall(tool: "capture_snapshot",
                arguments: ["bundle_id": "com.example.missing", "udid": .string(Sample.iPhoneUdid)],
                message: "No app with bundle identifier"),
        BadCall(tool: "capture_snapshot", arguments: capture.merging(["label": ""]) { $1 }, message: "must not be empty"),
        BadCall(tool: "capture_snapshot", arguments: capture.merging(["contents": "files"]) { $1 }, message: "must be one of"),
        BadCall(tool: "capture_snapshot", arguments: capture.merging(["terminate_app": "yes"]) { $1 }, message: "must be a boolean"),
        BadCall(tool: "diff_snapshot",
                arguments: ["snapshot_id": "x"],
                message: "Pass exactly one of against_snapshot_id or against_live"),
        BadCall(tool: "diff_snapshot",
                arguments: ["snapshot_id": "x", "against_snapshot_id": "y", "against_live": true],
                message: "Pass exactly one of")
    ]

    @Test("Bad arguments are clear errors", arguments: badCalls)
    func rejectsBadArguments(call: BadCall) async {
        defer { fixture.remove() }

        let result = await fixture.registry().call(call.tool, arguments: call.arguments)

        #expect(result.failed)
        #expect(result.text.contains(call.message), "\(result.text)")
    }
}

private extension SnapshotToolTests {
    func captureId(_ registry: ToolRegistry, contents: String = "everything") async throws -> String {
        var arguments = captureArguments
        arguments["contents"] = .string(contents)
        let json = try await registry.json("capture_snapshot", arguments)

        return try #require((json["snapshot"] as? [String: Any])?["id"] as? String)
    }
}
