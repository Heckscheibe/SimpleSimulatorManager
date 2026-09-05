import Foundation
@testable import SimulatorManager

/// A throwaway `Library/Preferences` directory holding hand-written plists, so the UserDefaults
/// export can be exercised against known content instead of a real simulator container.
struct PreferencesFixtureDirectory {
    let url: URL

    init() throws {
        url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("preferences-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Writes a binary plist, the format real preferences use.
    func writePreferences(named fileName: String, contents: [String: Any]) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: contents, format: .binary, options: 0)
        try data.write(to: url.appendingPathComponent("\(fileName).plist"))
    }

    func writeCorruptedPreferences(named fileName: String) throws {
        try Data("not a property list".utf8).write(to: url.appendingPathComponent("\(fileName).plist"))
    }

    /// Preferences folders in real containers also hold unrelated files.
    func writeNonPlistFile(named fileName: String) throws {
        try Data("ignored".utf8).write(to: url.appendingPathComponent(fileName))
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
