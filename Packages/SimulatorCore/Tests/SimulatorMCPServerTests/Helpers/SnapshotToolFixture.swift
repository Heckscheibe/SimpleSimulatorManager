import Foundation
import MCP
@testable import SimulatorCore
import SimulatorCoreTestSupport
@testable import SimulatorMCPServer

/// ``SampleSimulators`` plus a throwaway snapshot store, and a terminate that only records — so
/// the snapshot tools run end to end against fixture containers without a booted simulator.
struct SnapshotToolFixture {
    let simulators: SampleSimulators
    let storeURL: URL
    let appActions = MockSimulatorAppActionService()

    init() throws {
        simulators = try SampleSimulators()
        storeURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("mcp-snapshot-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storeURL, withIntermediateDirectories: true)

        try write("hello", at: "Documents/note.txt")
        try write(Data("SQLite format 3\0".utf8) + Data("v1 rows".utf8), at: "Library/Application Support/Model.sqlite")
        try write("wal", at: "Library/Application Support/Model.sqlite-wal")
    }

    var dataContainerURL: URL {
        simulators.notesOnIPhone.dataContainerURL
    }

    func registry(_ options: ServerOptions = ServerOptions(allowSnapshots: true)) -> ToolRegistry {
        let service = SimulatorQueryService(
            deviceLoader: DeviceLoader(devicesDirectoryURL: simulators.fixture.url),
            resetService: MockSimulatorResetService(),
            cleanupService: MockSimulatorCleanupService(),
            snapshotService: AppSnapshotService(store: AppSnapshotStore(rootURL: storeURL), appActionService: appActions)
        )

        return ToolRegistry(options: options, service: service)
    }

    @discardableResult
    func write(_ contents: String, at relativePath: String) throws -> URL {
        try write(Data(contents.utf8), at: relativePath)
    }

    @discardableResult
    func write(_ data: Data, at relativePath: String) throws -> URL {
        let url = dataContainerURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)

        return url
    }

    func contents(at relativePath: String) -> String? {
        (try? Data(contentsOf: dataContainerURL.appendingPathComponent(relativePath))).map { String(decoding: $0, as: UTF8.self) }
    }

    func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: dataContainerURL.appendingPathComponent(relativePath).path)
    }

    /// Gives the installed app a version, as installing a newer build would.
    func setInstalledVersion(_ version: String) throws {
        let infoPlistURL = simulators.notesOnIPhone.bundleURL.appendingPathComponent("Info.plist")
        var info = try PropertyListSerialization.propertyList(from: Data(contentsOf: infoPlistURL), format: nil) as? [String: Any] ?? [:]
        info["CFBundleShortVersionString"] = version
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: infoPlistURL)
    }

    func storedSnapshotCount() -> Int {
        AppSnapshotStore(rootURL: storeURL).allSnapshots().count
    }

    func remove() {
        simulators.remove()
        try? FileManager.default.removeItem(at: storeURL)
    }
}

extension ToolRegistry {
    /// Calls `name` and parses its JSON, recording an issue if the call failed.
    func json(_ name: String, _ arguments: [String: Value]) async throws -> [String: Any] {
        let result = await call(name, arguments: arguments)

        guard !result.failed else {
            throw ToolArgumentError(message: "\(name) failed: \(result.text)")
        }

        return try result.json()
    }
}
