import MCP
@testable import SimulatorMCPServer
import Testing

@Suite("Tool listing and flag gating")
struct ToolListingTests {
    private static let readOnlyTools: Set<String> = [
        "list_devices", "list_apps", "find_app", "get_app_containers", "list_app_groups",
        "list_recent_apps", "list_cleanup_candidates", "list_snapshots"
    ]
    private static let destructiveTools: Set<String> = ["erase_device", "erase_all_simulators", "delete_cleanup_candidate"]
    private static let snapshotTools: Set<String> = ["capture_snapshot", "diff_snapshot", "restore_snapshot", "delete_snapshot"]

    private func toolNames(_ options: ServerOptions) -> [String] {
        ToolRegistry(options: options).tools.map(\.name)
    }

    @Test("Without flags only the read-only tools and shutdown_all_simulators are listed")
    func listsNineToolsWithoutFlags() {
        let names = toolNames(ServerOptions())

        #expect(names.count == 9)
        #expect(Set(names) == Self.readOnlyTools.union(["shutdown_all_simulators"]))
    }

    @Test("--allow-user-defaults adds read_user_defaults")
    func listsTenToolsWithUserDefaults() {
        let names = toolNames(ServerOptions(allowUserDefaults: true))

        #expect(names.count == 10)
        #expect(names.contains("read_user_defaults"))
        #expect(Set(names).isDisjoint(with: Self.destructiveTools))
        #expect(Set(names).isDisjoint(with: Self.snapshotTools))
    }

    @Test("--allow-destructive adds the three destructive tools")
    func listsTwelveToolsWithDestructive() {
        let names = toolNames(ServerOptions(allowDestructive: true))

        #expect(names.count == 12)
        #expect(Self.destructiveTools.isSubset(of: Set(names)))
        #expect(!names.contains("read_user_defaults"))
        #expect(Set(names).isDisjoint(with: Self.snapshotTools))
    }

    @Test("--allow-snapshots adds the four snapshot tools and nothing else")
    func listsThirteenToolsWithSnapshots() {
        let names = toolNames(ServerOptions(allowSnapshots: true))

        #expect(names.count == 13)
        #expect(Self.snapshotTools.isSubset(of: Set(names)))
        #expect(Set(names).isDisjoint(with: Self.destructiveTools))
        #expect(!names.contains("read_user_defaults"))
    }

    @Test("All flags list all seventeen tools")
    func listsEveryToolWithAllFlags() {
        let names = toolNames(.allFlags)

        #expect(names.count == 17)
        #expect(Set(names) == Set(SimulatorTool.allCases.map(\.rawValue)))
    }

    @Test("shutdown_all_simulators is listed without flags and is not destructive")
    func shutdownIsAlwaysAvailable() throws {
        let tool = try #require(ToolRegistry(options: ServerOptions()).tools.first { $0.name == "shutdown_all_simulators" })

        #expect(tool.annotations.destructiveHint == false)
        #expect(tool.annotations.idempotentHint == true)
        #expect(tool.annotations.readOnlyHint == false)
    }

    @Test("Annotations mark read-only and destructive tools")
    func annotationsMatchBehaviour() {
        for tool in ToolRegistry(options: .allFlags).tools {
            if Self.readOnlyTools.contains(tool.name) || ["read_user_defaults", "diff_snapshot"].contains(tool.name) {
                #expect(tool.annotations.readOnlyHint == true, "\(tool.name)")
                #expect(tool.annotations.destructiveHint == false, "\(tool.name)")
            } else if Self.destructiveTools.contains(tool.name) || ["restore_snapshot", "delete_snapshot"].contains(tool.name) {
                #expect(tool.annotations.readOnlyHint == false, "\(tool.name)")
                #expect(tool.annotations.destructiveHint == true, "\(tool.name)")
            }
            #expect(tool.annotations.openWorldHint == false, "\(tool.name)")
        }
    }

    @Test("No tool accepts a path argument")
    func schemasTakeIdentifiersOnly() {
        for tool in ToolRegistry(options: .allFlags).tools {
            let properties = tool.inputSchema.objectValue?["properties"]?.objectValue ?? [:]
            #expect(properties.keys.allSatisfy { !$0.localizedCaseInsensitiveContains("path") }, "\(tool.name)")
            #expect(tool.inputSchema.objectValue?["additionalProperties"] == .bool(false), "\(tool.name)")
        }
    }

    @Test("Calling a gated tool without its flag names the flag", arguments: [
        ("read_user_defaults", "--allow-user-defaults"),
        ("erase_device", "--allow-destructive"),
        ("erase_all_simulators", "--allow-destructive"),
        ("delete_cleanup_candidate", "--allow-destructive"),
        ("capture_snapshot", "--allow-snapshots"),
        ("diff_snapshot", "--allow-snapshots"),
        ("restore_snapshot", "--allow-snapshots"),
        ("delete_snapshot", "--allow-snapshots")
    ])
    func gatedToolNamesItsFlag(tool: String, flag: String) async {
        let resetService = MockSimulatorResetService()
        let cleanupService = MockSimulatorCleanupService(candidates: [CleanupCandidateFactory.simctlCandidate()])
        let registry = ToolRegistry(options: ServerOptions(),
                                    service: SimulatorQueryService(resetService: resetService, cleanupService: cleanupService))

        let result = await registry.call(tool, arguments: ["udid": "x", "id": "simctl-x"])

        #expect(result.failed)
        #expect(result.text.contains(flag))
        #expect(resetService.calls.isEmpty)
        #expect(cleanupService.deleted.isEmpty)
    }

    @Test("Neither of the other flags unlocks the snapshot tools", arguments: [
        ServerOptions(allowUserDefaults: true),
        ServerOptions(allowDestructive: true)
    ])
    func otherFlagsDoNotUnlockSnapshots(options: ServerOptions) async {
        let result = await ToolRegistry(options: options).call("restore_snapshot", arguments: ["snapshot_id": "x"])

        #expect(result.failed)
        #expect(result.text.contains("--allow-snapshots"))
    }

    @Test("The user-defaults flag does not unlock destructive tools")
    func userDefaultsFlagDoesNotUnlockDestructiveTools() async {
        let resetService = MockSimulatorResetService()
        let registry = ToolRegistry(options: ServerOptions(allowUserDefaults: true),
                                    service: SimulatorQueryService(resetService: resetService))

        let result = await registry.call("erase_all_simulators", arguments: nil)

        #expect(result.failed)
        #expect(result.text.contains("--allow-destructive"))
        #expect(resetService.calls.isEmpty)
    }

    @Test("An unknown tool is an error")
    func unknownToolIsAnError() async {
        let result = await ToolRegistry(options: .allFlags).call("format_disk", arguments: nil)

        #expect(result.failed)
        #expect(result.text.contains("format_disk"))
    }
}
