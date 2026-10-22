import Foundation
import MCP
import SimulatorCore
@testable import SimulatorMCPServer
import Testing

/// Drives the real server through an MCP client over `InMemoryTransport`, against a fixture
/// devices directory and mocked simctl-backed services.
@Suite("End to end over InMemoryTransport")
struct EndToEndTests {
    private let simulators: SampleSimulators

    init() throws {
        simulators = try SampleSimulators()
    }

    private func withClient<T>(
        _ options: ServerOptions = ServerOptions(),
        cleanupService: MockSimulatorCleanupService = MockSimulatorCleanupService(),
        _ body: (Client) async throws -> T
    ) async throws -> T {
        try await withClient(registry: simulators.registry(options, cleanupService: cleanupService), body)
    }

    private func withClient<T>(registry: ToolRegistry, _ body: (Client) async throws -> T) async throws -> T {
        let server = await SimulatorMCPServer.makeServer(registry: registry)
        let client = Client(name: "test-client", version: "1.0")
        let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()

        // Torn down on every path, so a failing expectation inside `body` leaves no server running.
        do {
            try await server.start(transport: serverTransport)
            try await client.connect(transport: clientTransport)
            let result = try await body(client)
            await client.disconnect()
            await server.stop()
            return result
        } catch {
            await client.disconnect()
            await server.stop()
            throw error
        }
    }

    private func callTool(_ client: Client, _ name: String, _ arguments: [String: Value]? = nil) async throws -> [String: Any] {
        let (content, isError) = try await client.callTool(name: name, arguments: arguments)
        let result = CallTool.Result(content: content, isError: isError)
        #expect(isError != true, "\(name): \(result.text)")
        return try result.json()
    }

    @Test("The server introduces itself and lists the default tools")
    func listsDefaultTools() async throws {
        defer { simulators.remove() }

        let names = try await withClient { client in
            try await client.listTools().tools.map(\.name)
        }

        #expect(names.count == 9)
        #expect(names.contains("shutdown_all_simulators"))
    }

    @Test("All flags list seventeen tools over the wire")
    func listsAllToolsWithAllFlags() async throws {
        defer { simulators.remove() }

        let count = try await withClient(.allFlags) { client in
            try await client.listTools().tools.count
        }

        #expect(count == 17)
    }

    @Test("The migration loop over the wire: capture, change, diff, restore, diff again")
    func snapshotLoop() async throws {
        let fixture = try SnapshotToolFixture()

        defer {
            simulators.remove()
            fixture.remove()
        }

        try await withClient(registry: fixture.registry()) { client in
            let capture = try await callTool(client, "capture_snapshot", [
                "bundle_id": .string(Sample.appBundleId), "udid": .string(Sample.iPhoneUdid), "contents": "databases"
            ])
            let id = try #require((capture["snapshot"] as? [String: Any])?["id"] as? String)

            try fixture.write(Data("SQLite format 3\0".utf8) + Data("migrated".utf8), at: "Library/Application Support/Model.sqlite")
            try fixture.write("new wal", at: "Library/Application Support/Model.sqlite-wal")

            let changed = try await callTool(client, "diff_snapshot", ["snapshot_id": .string(id), "against_live": true])
            #expect(changed["hasChanges"] as? Bool == true)

            let restore = try await callTool(client, "restore_snapshot", ["snapshot_id": .string(id)])
            #expect(restore["restored"] as? Bool == true)

            let unchanged = try await callTool(client, "diff_snapshot", ["snapshot_id": .string(id), "against_live": true])
            #expect(unchanged["hasChanges"] as? Bool == false)
            #expect(fixture.contents(at: "Library/Application Support/Model.sqlite-wal") == "wal")
        }
    }

    @Test("list_devices returns every simulator and filters by platform and state")
    func listDevices() async throws {
        defer { simulators.remove() }

        let (all, watches, running) = try await withClient { client in
            try (await callTool(client, "list_devices"),
                 await callTool(client, "list_devices", ["platform": .string("WATCH")]),
                 await callTool(client, "list_devices", ["state": .string("running")]))
        }

        let devices = try #require(all["devices"] as? [[String: Any]])
        #expect(devices.compactMap { $0["name"] as? String } == ["Apple Watch", "iPad Air", "iPhone 16 Pro"])

        let iPhone = try #require(devices.first { $0["udid"] as? String == Sample.iPhoneUdid })
        #expect(iPhone["osVersion"] as? String == "iOS 26.1")
        #expect(iPhone["platform"] as? String == "iPhone")
        #expect(iPhone["state"] as? String == "running")
        #expect(iPhone["lastBootedAt"] as? String == ISO8601DateFormatter().string(from: Sample.lastBootedAt))
        #expect(iPhone["deviceFolder"] as? String == simulators.fixture.deviceURL(udid: Sample.iPhoneUdid).path)

        #expect((watches["devices"] as? [[String: Any]])?.compactMap { $0["udid"] as? String } == [Sample.watchUdid])
        #expect((running["devices"] as? [[String: Any]])?.compactMap { $0["udid"] as? String } == [Sample.iPhoneUdid])
    }

    @Test("list_apps returns a device's apps with the domains the menu offers")
    func listApps() async throws {
        defer { simulators.remove() }

        let result = try await withClient { client in
            try await callTool(client, "list_apps", ["udid": .string(Sample.iPhoneUdid)])
        }

        let apps = try #require(result["apps"] as? [[String: Any]])
        #expect(apps.compactMap { $0["bundleIdentifier"] as? String } == [Sample.appBundleId, Sample.otherAppBundleId])

        let notes = try #require(apps.first)
        #expect(notes["kind"] as? String == "iOS")
        #expect(notes["userDefaultsDomains"] as? [String] == [Sample.appBundleId, Sample.suiteDomain])
        #expect(notes["contentModifiedAt"] as? String == ISO8601DateFormatter().string(from: Sample.newerChange))
    }

    @Test("An empty simulator lists no apps but still succeeds")
    func emptySimulatorListsNoApps() async throws {
        defer { simulators.remove() }

        let result = try await withClient { client in
            try await callTool(client, "list_apps", ["udid": .string(Sample.watchUdid)])
        }

        #expect((result["apps"] as? [Any])?.isEmpty == true)
    }

    @Test("find_app returns every simulator that has the app")
    func findApp() async throws {
        defer { simulators.remove() }

        let result = try await withClient { client in
            try await callTool(client, "find_app", ["bundle_id": .string(Sample.appBundleId)])
        }

        let installations = try #require(result["installations"] as? [[String: Any]])
        let udids = installations.compactMap { ($0["device"] as? [String: Any])?["udid"] as? String }
        #expect(Set(udids) == [Sample.iPhoneUdid, Sample.iPadUdid])
    }

    @Test("An app group belongs to apps it is a dot-separated prefix of, not to any substring match")
    func appGroupAssociation() async throws {
        defer { simulators.remove() }
        try simulators.fixture.writeApp(bundleIdentifier: "com.example.notesplus", name: "Notes Plus", onDeviceWithUdid: Sample.iPhoneUdid)
        try simulators.fixture.writeApp(bundleIdentifier: "com.example.notes.widget", name: "Notes Widget", onDeviceWithUdid: Sample.iPhoneUdid)

        let (plus, widget) = try await withClient { client in
            try await (callTool(client, "get_app_containers", ["udid": .string(Sample.iPhoneUdid), "bundle_id": .string("com.example.notesplus")]),
                       callTool(client, "get_app_containers", ["udid": .string(Sample.iPhoneUdid), "bundle_id": .string("com.example.notes.widget")]))
        }

        #expect((plus["appGroups"] as? [Any])?.isEmpty == true)
        #expect((widget["appGroups"] as? [[String: Any]])?.compactMap { $0["identifier"] as? String } == [Sample.appGroupId])
    }

    @Test("get_app_containers returns the menu's folders and the app's groups")
    func getAppContainers() async throws {
        defer { simulators.remove() }

        let result = try await withClient { client in
            try await callTool(client, "get_app_containers", [
                "udid": .string(Sample.iPhoneUdid),
                "bundle_id": .string(Sample.appBundleId)
            ])
        }

        let app = simulators.notesOnIPhone
        #expect(result["dataContainer"] as? String == app.dataContainerURL.path)
        #expect(result["bundleContainer"] as? String == app.bundleURL.deletingLastPathComponent().path)
        #expect(result["appBundle"] as? String == app.bundleURL.path)
        #expect(result["preferencesFolder"] as? String == app.dataContainerURL.appendingPathComponent("Library/Preferences").path)

        let groups = try #require(result["appGroups"] as? [[String: Any]])
        #expect(groups.compactMap { $0["identifier"] as? String } == [Sample.appGroupId])
        #expect(groups.first?["groupFolder"] as? String == simulators.appGroupURL.path)
    }

    @Test("list_app_groups returns the groups of a device")
    func listAppGroups() async throws {
        defer { simulators.remove() }

        let (iPhone, iPad) = try await withClient { client in
            try (await callTool(client, "list_app_groups", ["udid": .string(Sample.iPhoneUdid)]),
                 await callTool(client, "list_app_groups", ["udid": .string(Sample.iPadUdid)]))
        }

        let groups = try #require(iPhone["appGroups"] as? [[String: Any]])
        #expect(groups.compactMap { $0["identifier"] as? String } == [Sample.appGroupId])
        #expect(groups.first?["userDefaultsDomains"] as? [String] == [Sample.appGroupId])
        #expect((iPad["appGroups"] as? [Any])?.isEmpty == true)
    }

    @Test("list_recent_apps follows the menu's recent-apps rule")
    func listRecentApps() async throws {
        defer { simulators.remove() }

        let result = try await withClient { client in
            try await callTool(client, "list_recent_apps")
        }

        let expected = try #require(DeviceLoader(devicesDirectoryURL: simulators.fixture.url).loadDevices())
        let menuOrder = RecentApps.initial(from: expected.initialAppChanges).map { "\($0.app.bundleIdentifier)@\($0.device.udid)" }
        let recentApps = try #require(result["recentApps"] as? [[String: Any]])
        let order = recentApps.compactMap { entry -> String? in
            guard let app = entry["app"] as? [String: Any], let bundleId = app["bundleIdentifier"] as? String,
                  let udid = entry["udid"] as? String else {
                return nil
            }

            return "\(bundleId)@\(udid)"
        }

        #expect(order == menuOrder)
        #expect(order.first == "\(Sample.appBundleId)@\(Sample.iPhoneUdid)")
    }

    @Test("read_user_defaults returns exactly the menu's export for an app and for an app group")
    func readUserDefaultsMatchesExport() async throws {
        defer { simulators.remove() }

        let (appText, groupText, domainText) = try await withClient(ServerOptions(allowUserDefaults: true)) { client in
            let app = try await client.callTool(name: "read_user_defaults", arguments: [
                "udid": .string(Sample.iPhoneUdid),
                "bundle_id": .string(Sample.appBundleId)
            ])
            let group = try await client.callTool(name: "read_user_defaults", arguments: [
                "udid": .string(Sample.iPhoneUdid),
                "app_group_id": .string(Sample.appGroupId)
            ])
            let domain = try await client.callTool(name: "read_user_defaults", arguments: [
                "udid": .string(Sample.iPhoneUdid),
                "bundle_id": .string(Sample.appBundleId),
                "domain": .string(Sample.suiteDomain)
            ])
            return (CallTool.Result(content: app.content).text,
                    CallTool.Result(content: group.content).text,
                    CallTool.Result(content: domain.content).text)
        }

        let exporter = UserDefaultsExportService()
        let preferences = simulators.notesOnIPhone.dataContainerURL.appendingPathComponent("Library/Preferences")
        let groupPreferences = simulators.appGroupURL.appendingPathComponent("Library/Preferences")

        #expect(try appText == (exporter.exportJSON(fromPreferencesDirectoryAt: preferences, ownDomain: Sample.appBundleId, domain: nil)))
        #expect(try groupText == (exporter.exportJSON(fromPreferencesDirectoryAt: groupPreferences, ownDomain: Sample.appGroupId, domain: nil)))
        #expect(try domainText == (exporter.exportJSON(fromPreferencesDirectoryAt: preferences,
                                                       ownDomain: Sample.appBundleId,
                                                       domain: Sample.suiteDomain)))
        #expect(appText.contains("launchCount"))
        #expect(!appText.contains("com.apple.UIKit"))
    }

    @Test("list_cleanup_candidates returns the cleanup service's candidates")
    func listCleanupCandidates() async throws {
        defer { simulators.remove() }
        let cleanupService = MockSimulatorCleanupService(candidates: [
            CleanupCandidateFactory.simctlCandidate(),
            CleanupCandidateFactory.directoryCandidate()
        ])

        let result = try await withClient(cleanupService: cleanupService) { client in
            try await callTool(client, "list_cleanup_candidates")
        }

        let candidates = try #require(result["candidates"] as? [[String: Any]])
        #expect(candidates.compactMap { $0["id"] as? String } == ["simctl-44444444-4444-4444-4444-444444444444", "directory-ABC"])
    }

    @Test("A gated tool called over the wire is an error naming its flag")
    func gatedToolOverTheWire() async throws {
        defer { simulators.remove() }

        let (content, isError) = try await withClient { client in
            try await client.callTool(name: "erase_all_simulators")
        }

        #expect(isError == true)
        #expect(CallTool.Result(content: content).text.contains("--allow-destructive"))
    }
}
