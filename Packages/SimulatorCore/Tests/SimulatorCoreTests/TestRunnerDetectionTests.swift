import Foundation
import Testing
@testable import SimulatorCore
import SimulatorCoreTestSupport

@Suite("UI test runner detection")
struct TestRunnerDetectionTests {
    private let iPhoneUDID = "11111111-1111-1111-1111-111111111111"

    // MARK: - Predicate

    @Test("Accepted rules", arguments: [
        ("com.nicolashiller.FitFitrUITests.xctrunner", nil),
        ("com.facebook.WebDriverAgentRunner.xctrunner", nil),
        ("com.apple.test.WebDriverAgentRunner-Runner", nil),
        ("com.example.anything", "_XCTRunnerAppDelegate")
    ] as [(String, String?)])
    func acceptedRules(bundleIdentifier: String, sceneDelegate: String?) {
        #expect(TestRunnerApp.isRunner(bundleIdentifier: bundleIdentifier, sceneDelegateClassName: sceneDelegate))
    }

    @Test("Rejected heuristics stay visible", arguments: [
        // Hosts its own unit and snapshot tests, so embeds .xctest plugins: not a runner.
        ("com.nicolashiller.FitFitr", nil),
        // A Flutter app's target is called Runner; its identifier is the app's own.
        ("com.example.flutterapp", nil),
        // Only the dot-delimited suffix counts.
        ("com.example.myxctrunner", nil),
        // The legacy rule needs both the prefix and the suffix.
        ("com.apple.test.Something", nil),
        ("com.example.UITests-Runner", nil),
        // An app naming its own scene delegate.
        ("com.example.app", "PorscheCompanion.SceneDelegate")
    ] as [(String, String?)])
    func rejectedHeuristics(bundleIdentifier: String, sceneDelegate: String?) {
        #expect(!TestRunnerApp.isRunner(bundleIdentifier: bundleIdentifier, sceneDelegateClassName: sceneDelegate))
    }

    // MARK: - Info.plist decoding

    @Test("An Info.plist without a scene manifest still decodes")
    func decodesWithoutSceneManifest() throws {
        let plist = try decode(manifest: nil)

        #expect(plist.sceneManifest == nil)
        #expect(!plist.isTestRunner)
    }

    @Test("The scene delegate class is read from the application role")
    func readsSceneDelegate() throws {
        let plist = try decode(manifest: [
            "UISceneConfigurations": [
                "UIWindowSceneSessionRoleApplication": [["UISceneDelegateClassName": "_XCTRunnerAppDelegate"]]
            ]
        ])

        #expect(plist.sceneManifest?.delegateClassName == "_XCTRunnerAppDelegate")
        #expect(plist.isTestRunner)
    }

    @Test("A scene manifest of an unexpected shape never fails the decode")
    func malformedManifestDoesNotThrow() throws {
        for manifest: Any in [
            ["UISceneConfigurations": [:]],
            ["UISceneConfigurations": ["UIWindowSceneSessionRoleApplication": "oops"]],
            ["UISceneConfigurations": ["UIWindowSceneSessionRoleApplication": [["UISceneDelegateClassName": 7]]]],
            ["UIApplicationSupportsMultipleScenes": false],
            "not a dictionary"
        ] {
            let plist = try decode(manifest: manifest)

            #expect(!plist.isTestRunner)
        }
    }

    // MARK: - Discovery

    @Test("Discovery flags runners and keeps them in the full set")
    func discoveryFlagsRunners() throws {
        let fixture = try DeviceFixtureDirectory()
        defer { fixture.remove() }

        try fixture.writeDevice(udid: iPhoneUDID, name: "iPhone 16 Pro")
        try fixture.writeApp(bundleIdentifier: "com.example.app", name: "Example", onDeviceWithUdid: iPhoneUDID)
        try fixture.writeApp(bundleIdentifier: "com.example.UITests.xctrunner",
                             name: "ExampleUITests-Runner",
                             onDeviceWithUdid: iPhoneUDID)
        try fixture.writeApp(bundleIdentifier: "com.example.hostapp",
                             name: "Runner",
                             onDeviceWithUdid: iPhoneUDID,
                             additionalInfoPlistEntries: ["CFBundleDisplayName": "Runner"])
        let sceneManifest: [String: Any] = [
            "UISceneConfigurations": [
                "UIWindowSceneSessionRoleApplication": [["UISceneDelegateClassName": "_XCTRunnerAppDelegate"]]
            ]
        ]
        try fixture.writeApp(bundleIdentifier: "com.example.sceneRunner",
                             name: "SceneRunner",
                             onDeviceWithUdid: iPhoneUDID,
                             additionalInfoPlistEntries: ["UIApplicationSceneManifest": sceneManifest])

        let device = try #require(DeviceLoader(devicesDirectoryURL: fixture.url).loadDevices()?.devices.first)
        let runners = Set(device.apps.filter(\.isTestRunner).map(\.bundleIdentifier))

        #expect(device.apps.count == 4)
        #expect(runners == ["com.example.UITests.xctrunner", "com.example.sceneRunner"])
    }

    @Test("App groups are the same whether or not runners are hidden")
    func appGroupsIgnoreRunners() throws {
        let fixture = try DeviceFixtureDirectory()
        defer { fixture.remove() }

        try fixture.writeDevice(udid: iPhoneUDID, name: "iPhone 16 Pro")
        try fixture.writeApp(bundleIdentifier: "com.example.UITests.xctrunner",
                             name: "ExampleUITests-Runner",
                             onDeviceWithUdid: iPhoneUDID)
        try fixture.writeAppGroup(identifier: "group.com.example.UITests.xctrunner", onDeviceWithUdid: iPhoneUDID)

        let device = try #require(DeviceLoader(devicesDirectoryURL: fixture.url).loadDevices()?.devices.first)

        #expect(device.apps.map(\.bundleIdentifier) == ["com.example.UITests.xctrunner"])
        #expect(device.appGroups.map(\.identifier) == ["group.com.example.UITests.xctrunner"])
    }
}

private extension TestRunnerDetectionTests {
    func decode(manifest: Any?) throws -> AppInfoPlist {
        var plist: [String: Any] = [
            "CFBundleIdentifier": "com.example.app",
            "CFBundleName": "Example",
            "DTPlatformName": "iphonesimulator"
        ]
        plist["UIApplicationSceneManifest"] = manifest
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)

        return try PropertyListDecoder().decode(AppInfoPlist.self, from: data)
    }
}
