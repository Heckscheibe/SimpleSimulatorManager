//
//  UserDefaultsExportServiceTests.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 25.08.26.
//

import Foundation
import Testing
@testable import SimulatorManager

@Suite("UserDefaultsExportService Tests")
struct UserDefaultsExportServiceTests {
    @Test("A binary preferences plist is exported as JSON")
    func binaryPlistIsExportedAsJSON() throws {
        let fixture = try PreferencesFixtureDirectory()
        defer { fixture.remove() }

        try fixture.writePreferences(named: "com.test.app", contents: [
            "userName": "Tester",
            "launchCount": 3,
            "onboarded": true,
            "lastLaunch": Date(timeIntervalSince1970: 0),
            "token": Data([0x01, 0x02]),
            "flags": ["a", "b"],
            "nested": ["level": 2]
        ])

        let json = try UserDefaultsExportService().exportJSON(fromPreferencesDirectoryAt: fixture.url,
                                                              preferredPlistName: "com.test.app")
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8))
        let root = try #require(parsed as? [String: Any])
        let nested = try #require(root["nested"] as? [String: Any])
        let token = try #require(root["token"] as? [String: Any])

        #expect(root["userName"] as? String == "Tester")
        #expect(root["launchCount"] as? Int == 3)
        #expect(root["lastLaunch"] as? String == "1970-01-01T00:00:00.000Z")
        #expect(root["flags"] as? [String] == ["a", "b"])
        #expect(nested["level"] as? Int == 2)
        #expect(token["base64"] as? String == Data([0x01, 0x02]).base64EncodedString())
        #expect(json.contains("\"onboarded\" : true"))
    }

    @Test("The subject's own plist wins over the system-managed ones next to it")
    func preferredPlistIsUsed() throws {
        let fixture = try PreferencesFixtureDirectory()
        defer { fixture.remove() }

        try fixture.writePreferences(named: "com.test.app", contents: ["source": "app"])
        try fixture.writePreferences(named: ".GlobalPreferences", contents: ["source": "global"])

        let json = try UserDefaultsExportService().exportJSON(fromPreferencesDirectoryAt: fixture.url,
                                                              preferredPlistName: "com.test.app")
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8))
        let root = try #require(parsed as? [String: Any])

        #expect(root["source"] as? String == "app")
        #expect(root.keys.count == 1)
    }

    @Test("A single differently named plist is exported at the top level")
    func singlePlistIsExportedTopLevel() throws {
        let fixture = try PreferencesFixtureDirectory()
        defer { fixture.remove() }

        try fixture.writePreferences(named: "com.other.identifier", contents: ["source": "only"])

        let json = try UserDefaultsExportService().exportJSON(fromPreferencesDirectoryAt: fixture.url,
                                                              preferredPlistName: "com.test.app")
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8))
        let root = try #require(parsed as? [String: Any])

        #expect(root["source"] as? String == "only")
    }

    @Test("Several plists and no preferred one are keyed by file name so nothing is dropped")
    func multiplePlistsAreKeyedByFileName() throws {
        let fixture = try PreferencesFixtureDirectory()
        defer { fixture.remove() }

        try fixture.writePreferences(named: "com.other.one", contents: ["source": "one"])
        try fixture.writePreferences(named: "com.other.two", contents: ["source": "two"])

        let json = try UserDefaultsExportService().exportJSON(fromPreferencesDirectoryAt: fixture.url,
                                                              preferredPlistName: "com.test.app")
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8))
        let root = try #require(parsed as? [String: Any])
        let first = try #require(root["com.other.one.plist"] as? [String: Any])
        let second = try #require(root["com.other.two.plist"] as? [String: Any])

        #expect(first["source"] as? String == "one")
        #expect(second["source"] as? String == "two")
    }

    @Test("Files that are not plists are ignored")
    func nonPlistFilesAreIgnored() throws {
        let fixture = try PreferencesFixtureDirectory()
        defer { fixture.remove() }

        try fixture.writePreferences(named: "com.test.app", contents: ["source": "app"])
        try fixture.writeNonPlistFile(named: ".DS_Store")

        let json = try UserDefaultsExportService().exportJSON(fromPreferencesDirectoryAt: fixture.url,
                                                              preferredPlistName: "com.test.app")
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8))
        let root = try #require(parsed as? [String: Any])

        #expect(root["source"] as? String == "app")
    }

    @Test("An empty preferences folder reports that there is nothing to export")
    func emptyFolderThrows() throws {
        let fixture = try PreferencesFixtureDirectory()
        defer { fixture.remove() }

        #expect(throws: UserDefaultsExportService.ExportError.noPreferencesFound) {
            try UserDefaultsExportService().exportJSON(fromPreferencesDirectoryAt: fixture.url,
                                                       preferredPlistName: "com.test.app")
        }
    }

    @Test("A missing preferences folder reports that there is nothing to export")
    func missingFolderThrows() throws {
        let missingURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("missing-preferences-\(UUID().uuidString)", isDirectory: true)

        #expect(throws: UserDefaultsExportService.ExportError.noPreferencesFound) {
            try UserDefaultsExportService().exportJSON(fromPreferencesDirectoryAt: missingURL,
                                                       preferredPlistName: "com.test.app")
        }
    }

    @Test("A preferences file that cannot be decoded reports the failure instead of exporting nothing")
    func corruptedPlistThrows() throws {
        let fixture = try PreferencesFixtureDirectory()
        defer { fixture.remove() }

        try fixture.writeCorruptedPreferences(named: "com.test.app")

        #expect(throws: UserDefaultsExportService.ExportError.unreadablePreferences(fileName: "com.test.app.plist")) {
            try UserDefaultsExportService().exportJSON(fromPreferencesDirectoryAt: fixture.url,
                                                       preferredPlistName: "com.test.app")
        }
    }

    @Test("One unreadable file among several does not lose the readable ones")
    func unreadableFileAmongSeveralIsSkipped() throws {
        let fixture = try PreferencesFixtureDirectory()
        defer { fixture.remove() }

        try fixture.writePreferences(named: "com.other.one", contents: ["source": "one"])
        try fixture.writeCorruptedPreferences(named: "com.other.two")

        let json = try UserDefaultsExportService().exportJSON(fromPreferencesDirectoryAt: fixture.url,
                                                              preferredPlistName: "com.test.app")
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8))
        let root = try #require(parsed as? [String: Any])

        #expect(root.keys.contains("com.other.one.plist"))
        #expect(!root.keys.contains("com.other.two.plist"))
    }
}
