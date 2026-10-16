import Foundation
import MCP
@testable import SimulatorMCPServer
import Testing

@Suite("Argument validation and unknown identifiers")
struct ArgumentValidationTests {
    private let simulators: SampleSimulators

    init() throws {
        simulators = try SampleSimulators()
    }

    // MARK: - Shape of the arguments

    @Test("Missing required arguments are errors", arguments: [
        ("list_apps", "udid"),
        ("find_app", "bundle_id"),
        ("get_app_containers", "udid"),
        ("list_app_groups", "udid"),
        ("read_user_defaults", "udid"),
        ("erase_device", "udid"),
        ("delete_cleanup_candidate", "id")
    ])
    func missingRequiredArgument(tool: String, argument: String) async {
        defer { simulators.remove() }

        let result = await simulators.registry(.allFlags).call(tool, arguments: nil)

        #expect(result.failed)
        #expect(result.text.contains("Missing required argument \(argument)"))
    }

    @Test("get_app_containers requires a bundle_id as well")
    func containersRequireBundleId() async {
        defer { simulators.remove() }

        let result = await simulators.registry().call("get_app_containers", arguments: ["udid": .string(Sample.iPhoneUdid)])

        #expect(result.failed)
        #expect(result.text.contains("bundle_id"))
    }

    @Test("Identifiers must be non-empty strings", arguments: [Value.int(4), .bool(true), .string(""), .string("  "), .array([])])
    func identifiersMustBeNonEmptyStrings(value: Value) async {
        defer { simulators.remove() }

        let result = await simulators.registry().call("list_apps", arguments: ["udid": value])

        #expect(result.failed)
        #expect(result.text.contains("udid"))
    }

    @Test("Unknown arguments are rejected instead of ignored")
    func unknownArgumentsAreRejected() async {
        defer { simulators.remove() }

        let result = await simulators.registry().call("list_apps", arguments: [
            "udid": .string(Sample.iPhoneUdid),
            "path": .string("/etc")
        ])

        #expect(result.failed)
        #expect(result.text.contains("Unknown argument path"))
    }

    @Test("Tools without arguments reject any argument", arguments: ["list_cleanup_candidates", "shutdown_all_simulators", "erase_all_simulators"])
    func argumentlessToolsRejectArguments(tool: String) async {
        defer { simulators.remove() }
        let resetService = MockSimulatorResetService()

        let result = await simulators.registry(.allFlags, resetService: resetService).call(tool, arguments: ["udid": .string(Sample.iPhoneUdid)])

        #expect(result.failed)
        #expect(resetService.calls.isEmpty)
    }

    @Test("list_devices rejects platform and state values it does not know")
    func listDevicesRejectsUnknownFilters() async {
        defer { simulators.remove() }
        let registry = simulators.registry()

        let platform = await registry.call("list_devices", arguments: ["platform": .string("android")])
        let state = await registry.call("list_devices", arguments: ["state": .string("suspended")])

        #expect(platform.failed)
        #expect(platform.text.contains("iPhone"))
        #expect(state.failed)
        #expect(state.text.contains("running"))
    }

    @Test("list_recent_apps limit must be an integer")
    func limitMustBeAnInteger() async {
        defer { simulators.remove() }
        let registry = simulators.registry()

        let text = await registry.call("list_recent_apps", arguments: ["limit": .string("5")])
        let fraction = await registry.call("list_recent_apps", arguments: ["limit": .double(2.5)])
        let integralDouble = await registry.call("list_recent_apps", arguments: ["limit": .double(1)])

        #expect(text.failed)
        #expect(fraction.failed)
        #expect(!integralDouble.failed)
    }

    @Test("A limit beyond Int's range is clamped like any other", arguments: [1e20, -1e20])
    func hugeLimitIsClamped(limit: Double) async throws {
        defer { simulators.remove() }

        let result = await simulators.registry().call("list_recent_apps", arguments: ["limit": .double(limit)])
        let recentApps = try #require(try result.json()["recentApps"] as? [Any])

        #expect(recentApps.count == (limit > 0 ? 3 : 1))
    }

    @Test("list_recent_apps clamps limit to 1…20", arguments: [(-5, 1), (0, 1), (1, 1), (2, 2), (500, 3)])
    func limitIsClamped(limit: Int, expectedCount: Int) async throws {
        defer { simulators.remove() }

        let result = await simulators.registry().call("list_recent_apps", arguments: ["limit": .int(limit)])
        let recentApps = try #require(try result.json()["recentApps"] as? [Any])

        // Three apps exist in the fixture, so an upper clamp shows as "all of them".
        #expect(recentApps.count == expectedCount)
    }

    @Test("read_user_defaults needs exactly one of bundle_id and app_group_id")
    func userDefaultsSubjectIsExclusive() async {
        defer { simulators.remove() }
        let registry = simulators.registry(ServerOptions(allowUserDefaults: true))

        let neither = await registry.call("read_user_defaults", arguments: ["udid": .string(Sample.iPhoneUdid)])
        let both = await registry.call("read_user_defaults", arguments: [
            "udid": .string(Sample.iPhoneUdid),
            "bundle_id": .string(Sample.appBundleId),
            "app_group_id": .string(Sample.appGroupId)
        ])

        #expect(neither.failed)
        #expect(both.failed)
        #expect(both.text.contains("exactly one"))
    }

    // MARK: - Unknown identifiers

    @Test("An unknown UDID is an error for every tool that takes one", arguments: [
        "list_apps", "get_app_containers", "list_app_groups", "read_user_defaults", "erase_device"
    ])
    func unknownUdid(tool: String) async {
        defer { simulators.remove() }
        let resetService = MockSimulatorResetService()

        var arguments: [String: Value] = ["udid": .string(Sample.unknownUdid)]
        if tool == "get_app_containers" || tool == "read_user_defaults" {
            arguments["bundle_id"] = .string(Sample.appBundleId)
        }

        let result = await simulators.registry(.allFlags, resetService: resetService).call(tool, arguments: arguments)

        #expect(result.failed)
        #expect(result.text.contains(Sample.unknownUdid))
        #expect(resetService.calls.isEmpty)
    }

    @Test("A lowercased UDID names the same simulator")
    func lowercasedUdidIsTheSameSimulator() async throws {
        defer { simulators.remove() }
        // Relies on the devices directory's volume being case-insensitive, as macOS volumes are by default.
        let udid = "ABCDEF01-2345-6789-ABCD-EF0123456789"
        try simulators.fixture.writeDevice(udid: udid, name: "iPhone 17")

        let result = await simulators.registry().call("list_apps", arguments: ["udid": .string(udid.lowercased())])

        #expect(!result.failed)
    }

    @Test("A UDID that walks out of the devices directory is unknown, not resolved")
    func traversalUdidIsUnknown() async {
        defer { simulators.remove() }

        let result = await simulators.registry().call("list_apps", arguments: ["udid": .string("../\(Sample.iPhoneUdid)")])

        #expect(result.failed)
    }

    @Test("A folder whose device.plist names another UDID is not that device", arguments: [".", "..", "renamed-folder"])
    func folderMustMatchItsUdid(folder: String) async throws {
        defer { simulators.remove() }
        // A copy of the iPhone's device.plist in a folder with a different name.
        let copy = simulators.fixture.url.appendingPathComponent("renamed-folder")
        try FileManager.default.copyItem(at: simulators.fixture.deviceURL(udid: Sample.iPhoneUdid), to: copy)

        let result = await simulators.registry().call("list_apps", arguments: ["udid": .string(folder)])

        #expect(result.failed)
    }

    @Test("An unknown bundle identifier is an error, never an empty success")
    func unknownBundleIdentifier() async {
        defer { simulators.remove() }
        let registry = simulators.registry(ServerOptions(allowUserDefaults: true))

        let find = await registry.call("find_app", arguments: ["bundle_id": .string("com.example.missing")])
        let containers = await registry.call("get_app_containers", arguments: [
            "udid": .string(Sample.iPhoneUdid),
            "bundle_id": .string("com.example.missing")
        ])
        let defaults = await registry.call("read_user_defaults", arguments: [
            "udid": .string(Sample.iPhoneUdid),
            "bundle_id": .string("com.example.missing")
        ])

        for result in [find, containers, defaults] {
            #expect(result.failed)
            #expect(result.text.contains("com.example.missing"))
        }
    }

    @Test("An app installed elsewhere is unknown on a device that lacks it")
    func appMissingOnDevice() async {
        defer { simulators.remove() }

        let result = await simulators.registry().call("get_app_containers", arguments: [
            "udid": .string(Sample.iPadUdid),
            "bundle_id": .string(Sample.otherAppBundleId)
        ])

        #expect(result.failed)
        #expect(result.text.contains(Sample.iPadUdid))
    }

    @Test("An unknown app group identifier is an error")
    func unknownAppGroup() async {
        defer { simulators.remove() }

        let result = await simulators.registry(ServerOptions(allowUserDefaults: true)).call("read_user_defaults", arguments: [
            "udid": .string(Sample.iPhoneUdid),
            "app_group_id": .string("group.com.example.missing")
        ])

        #expect(result.failed)
        #expect(result.text.contains("group.com.example.missing"))
    }

    @Test("An unknown UserDefaults domain lists the available ones")
    func unknownDomain() async {
        defer { simulators.remove() }

        let result = await simulators.registry(ServerOptions(allowUserDefaults: true)).call("read_user_defaults", arguments: [
            "udid": .string(Sample.iPhoneUdid),
            "bundle_id": .string(Sample.appBundleId),
            "domain": .string("com.example.missing")
        ])

        #expect(result.failed)
        #expect(result.text.contains(Sample.suiteDomain))
    }

    @Test("An app without UserDefaults is an error rather than an empty document")
    func appWithoutUserDefaults() async {
        defer { simulators.remove() }

        let result = await simulators.registry(ServerOptions(allowUserDefaults: true)).call("read_user_defaults", arguments: [
            "udid": .string(Sample.iPhoneUdid),
            "bundle_id": .string(Sample.otherAppBundleId)
        ])

        #expect(result.failed)
        #expect(result.text.contains("has not written any UserDefaults"))
    }

    @Test("An unknown cleanup candidate id is an error and deletes nothing")
    func unknownCleanupCandidate() async {
        defer { simulators.remove() }
        let cleanupService = MockSimulatorCleanupService(candidates: [CleanupCandidateFactory.simctlCandidate()])

        let result = await simulators.registry(.allFlags, cleanupService: cleanupService)
            .call("delete_cleanup_candidate", arguments: ["id": .string("/Users/someone/Library")])

        #expect(result.failed)
        #expect(cleanupService.deleted.isEmpty)
    }

    @Test("A missing devices directory is an error")
    func missingDevicesDirectory() async {
        defer { simulators.remove() }
        let registry = ToolRegistry(options: ServerOptions(),
                                    service: SimulatorQueryService(deviceLoader: .init(devicesDirectoryURL: nil)))

        let result = await registry.call("list_devices", arguments: nil)

        #expect(result.failed)
    }
}
