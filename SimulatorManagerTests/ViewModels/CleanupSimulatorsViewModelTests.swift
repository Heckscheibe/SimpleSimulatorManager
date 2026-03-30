import Foundation
import Testing
@testable import SimulatorManager

@MainActor
@Suite("CleanupSimulatorsViewModel Tests")
struct CleanupSimulatorsViewModelTests {
    @Test("refresh loads cleanup candidates")
    func refreshLoadsCleanupCandidates() async throws {
        let deviceManager = MockDeviceManager()
        let cleanupService = MockSimulatorCleanupService()
        let candidate = makeCandidate(id: "simctl-test")

        await cleanupService.setCleanupCandidates([candidate])

        let viewModel = CleanupSimulatorsViewModel(
            cleanupService: cleanupService,
            deviceManager: deviceManager
        )

        viewModel.refreshCleanupCandidates()
        try await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.cleanupCandidates == [candidate])
        #expect(viewModel.errorMessage == nil)
        #expect(!viewModel.isLoadingCleanupCandidates)
    }

    @Test("delete removes candidate and refreshes devices")
    func deleteRemovesCandidateAndRefreshesDevices() async throws {
        let deviceManager = MockDeviceManager()
        let cleanupService = MockSimulatorCleanupService()
        let candidate = makeCandidate(id: "orphan-test")

        await cleanupService.setCleanupCandidates([candidate])

        let viewModel = CleanupSimulatorsViewModel(
            cleanupService: cleanupService,
            deviceManager: deviceManager
        )

        viewModel.refreshCleanupCandidates()
        try await Task.sleep(for: .milliseconds(50))
        viewModel.delete(candidate)
        try await Task.sleep(for: .milliseconds(50))

        #expect(deviceManager.resetAndLoadDevicesCalled)
        #expect(viewModel.cleanupCandidates.isEmpty)
        #expect(await cleanupService.deletedCandidateIDs == [candidate.id])
    }

    private func makeCandidate(id: String) -> SimulatorCleanupCandidate {
        SimulatorCleanupCandidate(
            id: id,
            name: "Broken Simulator",
            udid: "E95A4AE1-04A0-4C9B-8CF2-EDDD2F6CE053",
            simulatorPlatform: .iPhone,
            osVersion: "26.1",
            lastBootedAt: nil,
            diskUsageBytes: 1024,
            reasons: [.missingRuntime, .unavailable],
            detailMessage: "runtime profile not found",
            deletionMethod: .simctlDelete("E95A4AE1-04A0-4C9B-8CF2-EDDD2F6CE053")
        )
    }
}

private extension MockSimulatorCleanupService {
    func setCleanupCandidates(_ cleanupCandidates: [SimulatorCleanupCandidate]) {
        self.cleanupCandidates = cleanupCandidates
    }
}
