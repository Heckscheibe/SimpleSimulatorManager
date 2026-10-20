import Foundation
import Testing
@testable import SimulatorCore

@Suite("Snapshot export naming")
struct SnapshotExportNamingTests {
    /// 2026-10-20 12:30:05 UTC.
    static let date = Date(timeIntervalSince1970: 1_792_499_405)
    static let utc = TimeZone(identifier: "UTC")!

    @Test("Joins device, OS version, app name and date with underscores")
    func matchesPattern() {
        let name = SnapshotExportNaming.folderName(deviceName: "iPhone 16 Pro",
                                                   osVersion: "iOS 18.2",
                                                   appName: "My App",
                                                   date: Self.date,
                                                   timeZone: Self.utc)

        #expect(name == "iPhone-16-Pro_iOS-18.2_My-App_2026-10-20_12-30-05")
    }

    @Test("Formats the date in the given time zone")
    func usesTimeZone() throws {
        let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))

        let name = SnapshotExportNaming.folderName(deviceName: "iPad",
                                                   osVersion: "iPadOS 18.0",
                                                   appName: "App",
                                                   date: Self.date,
                                                   timeZone: berlin)

        #expect(name.hasSuffix("_2026-10-20_14-30-05"))
    }

    @Test("Keeps the platform in the OS version, so it is not iOS-only")
    func keepsPlatform() {
        let name = SnapshotExportNaming.folderName(deviceName: "Apple Vision Pro",
                                                   osVersion: "visionOS 2.1",
                                                   appName: "Spatial",
                                                   date: Self.date,
                                                   timeZone: Self.utc)

        #expect(name.hasPrefix("Apple-Vision-Pro_visionOS-2.1_Spatial_"))
    }

    @Test(
        "Replaces separators, path characters and whitespace inside a field",
        arguments: [
            ("iPhone 16 Pro (2nd generation)", "iPhone-16-Pro-(2nd-generation)"),
            ("Foo/Bar:Baz", "Foo-Bar-Baz"),
            ("snake_case_name", "snake-case-name"),
            ("  spaced   out  ", "spaced-out"),
            ("tab\tand\nnewline", "tab-and-newline"),
            ("dash - and - dash", "dash-and-dash"),
            (".hidden", "hidden"),
            ("Café 🚀", "Café-🚀"),
            ("天气 应用", "天气-应用")
        ]
    )
    func sanitisesField(input: String, expected: String) {
        #expect(SnapshotExportNaming.sanitizedField(input) == expected)
    }

    @Test("Never puts an underscore inside a field, so the fields can be split back out")
    func underscoreOnlySeparates() {
        let name = SnapshotExportNaming.folderName(deviceName: "a_b",
                                                   osVersion: "c_d",
                                                   appName: "e_f",
                                                   date: Self.date,
                                                   timeZone: Self.utc)
        let components = name.components(separatedBy: "_")

        #expect(Array(components.prefix(3)) == ["a-b", "c-d", "e-f"])
        #expect(components.dropFirst(3).joined(separator: "_") == "2026-10-20_12-30-05")
    }

    @Test("A field that sanitises to nothing becomes a placeholder")
    func emptyField() {
        #expect(SnapshotExportNaming.sanitizedField("") == "unknown")
        #expect(SnapshotExportNaming.sanitizedField(" _/: ") == "unknown")
    }

    @Test("Caps a long field without splitting a composed character")
    func capsLength() {
        let long = String(repeating: "👩‍👩‍👧‍👦", count: 60)

        let field = SnapshotExportNaming.sanitizedField(long)

        #expect(!field.isEmpty)
        #expect(field.allSatisfy { $0 == "👩‍👩‍👧‍👦" })
        #expect(field.decomposedStringWithCanonicalMapping.utf8.count <= SnapshotExportNaming.maximumFieldByteCount)
    }

    @Test("Keeps a short field whole")
    func shortFieldUncapped() {
        #expect(SnapshotExportNaming.sanitizedField("Simulator Manager Demo") == "Simulator-Manager-Demo")
    }

    @Test("Stays inside the file name limit with the longest possible fields")
    func fitsFileNameLimit() {
        let long = String(repeating: "ü", count: 200)

        let name = SnapshotExportNaming.folderName(deviceName: long,
                                                   osVersion: long,
                                                   appName: long,
                                                   date: Self.date,
                                                   timeZone: Self.utc)

        // Room left for the " 99" a collision can append.
        #expect(name.decomposedStringWithCanonicalMapping.utf8.count + 3 <= 255)
    }

    @Test("Appends a number rather than reusing a name that exists")
    func uniqueName() {
        let directory = URL(fileURLWithPath: "/tmp/snapshots", isDirectory: true)
        let taken: Set<String> = ["name", "name 2"]

        let url = SnapshotExportNaming.uniqueDestinationURL(in: directory, folderName: "name") { url in
            taken.contains(url.lastPathComponent)
        }

        #expect(url.lastPathComponent == "name 3")
        #expect(url.deletingLastPathComponent().path == directory.path)
    }

    @Test("Uses the name as-is when it is free")
    func freeName() {
        let directory = URL(fileURLWithPath: "/tmp/snapshots", isDirectory: true)

        let url = SnapshotExportNaming.uniqueDestinationURL(in: directory, folderName: "name") { _ in false }

        #expect(url.lastPathComponent == "name")
    }
}
