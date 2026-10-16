import Foundation
import MCP
@testable import SimulatorMCPServer
import Testing

/// `shutdown_all_simulators` and the destructive tools, against mocked simctl-backed services.
@Suite("Action tools")
struct ActionToolTests {
    private let simulators: SampleSimulators

    init() throws {
        simulators = try SampleSimulators()
    }

    @Test("shutdown_all_simulators works without flags")
    func shutdownAllSimulators() async {
        defer { simulators.remove() }
        let resetService = MockSimulatorResetService()

        let result = await simulators.registry(resetService: resetService).call("shutdown_all_simulators", arguments: nil)

        #expect(!result.failed)
        #expect(resetService.calls == [.shutDownAll])
    }

    @Test("erase_device erases a known simulator")
    func eraseDevice() async {
        defer { simulators.remove() }
        let resetService = MockSimulatorResetService()

        let result = await simulators.registry(ServerOptions(allowDestructive: true), resetService: resetService)
            .call("erase_device", arguments: ["udid": .string(Sample.iPadUdid)])

        #expect(!result.failed)
        #expect(result.text.contains(Sample.iPadUdid))
        #expect(resetService.calls == [.shutDownAndErase(udid: Sample.iPadUdid)])
    }

    @Test("erase_device never passes an unvalidated string to simctl", arguments: ["all", "booted", "--help"])
    func eraseDeviceRejectsSimctlKeywords(udid: String) async {
        defer { simulators.remove() }
        let resetService = MockSimulatorResetService()

        let result = await simulators.registry(ServerOptions(allowDestructive: true), resetService: resetService)
            .call("erase_device", arguments: ["udid": .string(udid)])

        #expect(result.failed)
        #expect(resetService.calls.isEmpty)
    }

    @Test("erase_all_simulators shuts down and resets every simulator")
    func eraseAllSimulators() async {
        defer { simulators.remove() }
        let resetService = MockSimulatorResetService()

        let result = await simulators.registry(ServerOptions(allowDestructive: true), resetService: resetService)
            .call("erase_all_simulators", arguments: nil)

        #expect(!result.failed)
        #expect(resetService.calls == [.shutDownAndResetAll])
    }

    @Test("delete_cleanup_candidate reloads the candidates and deletes the match")
    func deleteCleanupCandidate() async throws {
        defer { simulators.remove() }
        let target = CleanupCandidateFactory.directoryCandidate()
        let cleanupService = MockSimulatorCleanupService(candidates: [CleanupCandidateFactory.simctlCandidate(), target])

        let result = await simulators.registry(ServerOptions(allowDestructive: true), cleanupService: cleanupService)
            .call("delete_cleanup_candidate", arguments: ["id": .string(target.id)])

        #expect(!result.failed)
        #expect(cleanupService.loads == 1)
        #expect(cleanupService.deleted == [target])
        #expect(try (result.json()["deleted"] as? [String: Any])?["id"] as? String == target.id)
    }

    @Test("A candidate deleted once is unknown the second time")
    func deleteCleanupCandidateTwice() async {
        defer { simulators.remove() }
        let target = CleanupCandidateFactory.simctlCandidate()
        let cleanupService = MockSimulatorCleanupService(candidates: [target])
        let registry = simulators.registry(ServerOptions(allowDestructive: true), cleanupService: cleanupService)

        _ = await registry.call("delete_cleanup_candidate", arguments: ["id": .string(target.id)])
        let second = await registry.call("delete_cleanup_candidate", arguments: ["id": .string(target.id)])

        #expect(second.failed)
        #expect(cleanupService.deleted.count == 1)
    }

    @Test("A failing simctl call is reported as an error")
    func simctlFailureIsAnError() async {
        defer { simulators.remove() }

        let result = await simulators.registry(resetService: MockSimulatorResetService(shouldFail: true))
            .call("shutdown_all_simulators", arguments: nil)

        #expect(result.failed)
        #expect(result.text.contains("simctl failed"))
    }
}
