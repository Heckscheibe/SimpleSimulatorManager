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
    private func export(
        from fixture: PreferencesFixtureDirectory,
        ownDomain: String = "com.test.app",
        domain: String? = nil
    ) throws -> [String: Any] {
        let json = try UserDefaultsExportService().exportJSON(fromPreferencesDirectoryAt: fixture.url,
                                                              ownDomain: ownDomain,
                                                              domain: domain)
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8))

        return try #require(parsed as? [String: Any])
    }

    @Test("A binary preferences plist is exported as JSON under its domain")
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

        let root = try export(from: fixture)
        let standardDomain = try #require(root["com.test.app"] as? [String: Any])
        let nested = try #require(standardDomain["nested"] as? [String: Any])
        let token = try #require(standardDomain["token"] as? [String: Any])

        #expect(standardDomain["userName"] as? String == "Tester")
        #expect(standardDomain["launchCount"] as? Int == 3)
        #expect(standardDomain["lastLaunch"] as? String == "1970-01-01T00:00:00.000Z")
        #expect(standardDomain["flags"] as? [String] == ["a", "b"])
        #expect(nested["level"] as? Int == 2)
        #expect(token["base64"] as? String == Data([0x01, 0x02]).base64EncodedString())
    }

    @Test("Every suite the app wrote is exported next to its standard domain")
    func suitesAreExportedAlongsideTheStandardDomain() throws {
        let fixture = try PreferencesFixtureDirectory()
        defer { fixture.remove() }

        // What a real container looks like: the app's own domain plus the suites its SDKs created
        // with `UserDefaults(suiteName:)`.
        try fixture.writePreferences(named: "com.test.app", contents: ["source": "standard"])
        try fixture.writePreferences(named: "APMAnalyticsSuiteName", contents: ["source": "analytics"])
        try fixture.writePreferences(named: "com.firebase.FIRInstallations", contents: ["source": "firebase"])

        let root = try export(from: fixture)
        let standardDomain = try #require(root["com.test.app"] as? [String: Any])
        let analyticsSuite = try #require(root["APMAnalyticsSuiteName"] as? [String: Any])
        let firebaseSuite = try #require(root["com.firebase.FIRInstallations"] as? [String: Any])

        #expect(standardDomain["source"] as? String == "standard")
        #expect(analyticsSuite["source"] as? String == "analytics")
        #expect(firebaseSuite["source"] as? String == "firebase")
    }

    @Test("Domains the OS wrote on the app's behalf are left out")
    func systemDomainsAreExcluded() throws {
        let fixture = try PreferencesFixtureDirectory()
        defer { fixture.remove() }

        try fixture.writePreferences(named: "com.test.app", contents: ["source": "standard"])
        try fixture.writePreferences(named: ".GlobalPreferences", contents: ["source": "global"])
        try fixture.writePreferences(named: "com.apple.UIAutomation", contents: ["source": "system"])

        let root = try export(from: fixture)

        #expect(root.keys.sorted() == ["com.test.app"])
    }

    @Test("An app whose own domain looks system-managed still exports it")
    func ownDomainSurvivesTheSystemDomainFilter() throws {
        let fixture = try PreferencesFixtureDirectory()
        defer { fixture.remove() }

        try fixture.writePreferences(named: "com.apple.mobilesafari", contents: ["source": "app"])

        let root = try export(from: fixture, ownDomain: "com.apple.mobilesafari")
        let standardDomain = try #require(root["com.apple.mobilesafari"] as? [String: Any])

        #expect(standardDomain["source"] as? String == "app")
    }

    @Test("A container holding only system domains still exports something")
    func systemOnlyContainerFallsBackToEverything() throws {
        let fixture = try PreferencesFixtureDirectory()
        defer { fixture.remove() }

        try fixture.writePreferences(named: ".GlobalPreferences", contents: ["source": "global"])

        let root = try export(from: fixture)

        #expect(root.keys.sorted() == [".GlobalPreferences"])
    }

    @Test("Suites are exported even when the app never wrote its standard domain")
    func suitesWithoutStandardDomainAreExported() throws {
        let fixture = try PreferencesFixtureDirectory()
        defer { fixture.remove() }

        try fixture.writePreferences(named: "com.other.suite", contents: ["source": "suite"])

        let root = try export(from: fixture)
        let suite = try #require(root["com.other.suite"] as? [String: Any])

        #expect(suite["source"] as? String == "suite")
    }

    @Test("A single domain can be exported on its own, keeping the domain-keyed shape")
    func singleDomainCanBeExportedOnItsOwn() throws {
        let fixture = try PreferencesFixtureDirectory()
        defer { fixture.remove() }

        try fixture.writePreferences(named: "com.test.app", contents: ["source": "standard"])
        try fixture.writePreferences(named: "APMAnalyticsSuiteName", contents: ["source": "analytics"])

        let root = try export(from: fixture, domain: "APMAnalyticsSuiteName")
        let analyticsSuite = try #require(root["APMAnalyticsSuiteName"] as? [String: Any])

        #expect(root.keys.sorted() == ["APMAnalyticsSuiteName"])
        #expect(analyticsSuite["source"] as? String == "analytics")
    }

    @Test("A named domain is exported even when the filter would otherwise drop it")
    func namedSystemDomainIsExported() throws {
        let fixture = try PreferencesFixtureDirectory()
        defer { fixture.remove() }

        try fixture.writePreferences(named: "com.test.app", contents: ["source": "standard"])
        try fixture.writePreferences(named: ".GlobalPreferences", contents: ["source": "global"])

        let root = try export(from: fixture, domain: ".GlobalPreferences")

        #expect(root.keys.sorted() == [".GlobalPreferences"])
    }

    @Test("A domain that vanished since the menu was built reports the failure")
    func vanishedDomainThrows() throws {
        let fixture = try PreferencesFixtureDirectory()
        defer { fixture.remove() }

        try fixture.writePreferences(named: "com.test.app", contents: ["source": "standard"])

        #expect(throws: UserDefaultsExportService.ExportError.noPreferencesFound) {
            try UserDefaultsExportService().exportJSON(fromPreferencesDirectoryAt: fixture.url,
                                                       ownDomain: "com.test.app",
                                                       domain: "APMAnalyticsSuiteName")
        }
    }

    @Test("Files that are not plists are ignored")
    func nonPlistFilesAreIgnored() throws {
        let fixture = try PreferencesFixtureDirectory()
        defer { fixture.remove() }

        try fixture.writePreferences(named: "com.test.app", contents: ["source": "app"])
        try fixture.writeNonPlistFile(named: ".DS_Store")

        let root = try export(from: fixture)

        #expect(root.keys.sorted() == ["com.test.app"])
    }

    @Test("An empty preferences folder reports that there is nothing to export")
    func emptyFolderThrows() throws {
        let fixture = try PreferencesFixtureDirectory()
        defer { fixture.remove() }

        #expect(throws: UserDefaultsExportService.ExportError.noPreferencesFound) {
            try UserDefaultsExportService().exportJSON(fromPreferencesDirectoryAt: fixture.url,
                                                       ownDomain: "com.test.app",
                                                       domain: nil)
        }
    }

    @Test("A missing preferences folder reports that there is nothing to export")
    func missingFolderThrows() throws {
        let missingURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("missing-preferences-\(UUID().uuidString)", isDirectory: true)

        #expect(throws: UserDefaultsExportService.ExportError.noPreferencesFound) {
            try UserDefaultsExportService().exportJSON(fromPreferencesDirectoryAt: missingURL,
                                                       ownDomain: "com.test.app",
                                                       domain: nil)
        }
    }

    @Test("A preferences file that cannot be decoded reports the failure instead of exporting nothing")
    func corruptedPlistThrows() throws {
        let fixture = try PreferencesFixtureDirectory()
        defer { fixture.remove() }

        try fixture.writeCorruptedPreferences(named: "com.test.app")

        #expect(throws: UserDefaultsExportService.ExportError.unreadablePreferences(fileName: "com.test.app.plist")) {
            try UserDefaultsExportService().exportJSON(fromPreferencesDirectoryAt: fixture.url,
                                                       ownDomain: "com.test.app",
                                                       domain: nil)
        }
    }

    @Test("One unreadable domain does not cost the readable ones")
    func unreadableDomainAmongSeveralIsSkipped() throws {
        let fixture = try PreferencesFixtureDirectory()
        defer { fixture.remove() }

        try fixture.writePreferences(named: "com.test.app", contents: ["source": "app"])
        try fixture.writeCorruptedPreferences(named: "APMAnalyticsSuiteName")

        let root = try export(from: fixture)

        #expect(root.keys.sorted() == ["com.test.app"])
    }
}
