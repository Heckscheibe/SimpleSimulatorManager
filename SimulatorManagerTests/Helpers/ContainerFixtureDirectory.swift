import Foundation
@testable import SimulatorManager

/// A throwaway app container laid out like a real one — metadata plist, `Documents`,
/// `Library/Preferences`, `Library/Caches` and `tmp` — so snapshotting can be exercised without a
/// simulator.
struct ContainerFixtureDirectory {
    let url: URL

    init(name: String = "container") throws {
        url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("snapshot-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    @discardableResult
    func write(_ contents: String, at relativePath: String) throws -> URL {
        let fileURL = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: fileURL)

        return fileURL
    }

    /// Writes a defaults domain the way `UserDefaults` does: `<domain>.plist` in
    /// `Library/Preferences`.
    @discardableResult
    func writeDefaults(_ values: [String: Any], domain: String) throws -> URL {
        let fileURL = url
            .appendingPathComponent(SimulatorPaths.userDefaultsPath, isDirectory: true)
            .appendingPathComponent("\(domain).plist")
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)

        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
        try data.write(to: fileURL)

        return fileURL
    }

    /// The container metadata plist CoreSimulator uses to identify the container. Snapshots must
    /// never capture or overwrite it.
    func writeContainerMetadata(identifier: String) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["MCMMetadataIdentifier": identifier],
            format: .xml,
            options: 0
        )
        try data.write(to: url.appendingPathComponent(MetaDataPlist.fileName))
    }

    func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(relativePath).path)
    }

    func contents(at relativePath: String) -> String? {
        guard let data = try? Data(contentsOf: url.appendingPathComponent(relativePath)) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    func defaults(domain: String) -> [String: Any]? {
        let fileURL = url
            .appendingPathComponent(SimulatorPaths.userDefaultsPath, isDirectory: true)
            .appendingPathComponent("\(domain).plist")

        guard let data = try? Data(contentsOf: fileURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else {
            return nil
        }

        return plist as? [String: Any]
    }

    func removeItem(at relativePath: String) throws {
        try FileManager.default.removeItem(at: url.appendingPathComponent(relativePath))
    }

    /// Every file in the fixture, relative to its root, so a test can assert on the whole tree
    /// rather than on the handful of paths it happened to think of.
    func relativeFilePaths() -> Set<String> {
        var paths: Set<String> = []

        SnapshotContainerFiles.enumerateContainer(at: url, includeCaches: true) { _, relativePath, entry in
            if entry.isFile {
                paths.insert(relativePath)
            }
        }

        return paths
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

/// A throwaway snapshot root, so tests never write into the user's Application Support.
struct SnapshotStoreFixtureDirectory {
    let url: URL

    init() throws {
        url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("snapshot-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
