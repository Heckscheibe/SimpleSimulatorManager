import Foundation
import Testing
@testable import SimulatorManager

@Suite("Info.plist version decoding")
struct AppInfoPlistVersionTests {
    @Test("Reads both version keys")
    func readsVersions() throws {
        let plist = try Self.decode([
            "CFBundleName": "Acme",
            "CFBundleIdentifier": "com.acme.app",
            "DTPlatformName": "iphonesimulator",
            "CFBundleShortVersionString": "2.4.1",
            "CFBundleVersion": "1043"
        ])

        #expect(plist.cfBundleShortVersionString == "2.4.1")
        #expect(plist.cfBundleVersion == "1043")
    }

    @Test("Keeps the app when a version was written as a number instead of a string")
    func toleratesNumericVersion() throws {
        let plist = try Self.decode([
            "CFBundleName": "Acme",
            "CFBundleIdentifier": "com.acme.app",
            "DTPlatformName": "iphonesimulator",
            "CFBundleVersion": 42
        ])

        #expect(plist.cfBundleIdentifier == "com.acme.app")
        #expect(plist.cfBundleVersion == "42")
        #expect(plist.cfBundleShortVersionString == nil)
    }

    @Test("Reads a bundle that declares no version at all")
    func toleratesMissingVersions() throws {
        let plist = try Self.decode([
            "CFBundleName": "Acme",
            "CFBundleIdentifier": "com.acme.app",
            "DTPlatformName": "iphonesimulator"
        ])

        #expect(plist.cfBundleShortVersionString == nil)
        #expect(plist.cfBundleVersion == nil)
    }

    private static func decode(_ values: [String: Any]) throws -> AppInfoPlist {
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)

        return try PropertyListDecoder().decode(AppInfoPlist.self, from: data)
    }
}
