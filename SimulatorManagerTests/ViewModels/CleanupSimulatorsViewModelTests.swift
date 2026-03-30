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

    @Test("groups cleanup candidates by OS version")
    func groupsCleanupCandidatesByOSVersion() async throws {
        let deviceManager = MockDeviceManager()
        let cleanupService = MockSimulatorCleanupService()
        let latestCandidate = makeCandidate(id: "ios-18", osVersion: "iOS 18.5", diskUsageBytes: 4096)
        let firstOlderCandidate = makeCandidate(id: "ios-17-a", osVersion: "iOS 17.4", diskUsageBytes: 2048, name: "iPhone 15")
        let secondOlderCandidate = makeCandidate(id: "ios-17-b", osVersion: "iOS 17.4", diskUsageBytes: 1024, name: "iPhone 14")

        await cleanupService.setCleanupCandidates([firstOlderCandidate, latestCandidate, secondOlderCandidate])

        let viewModel = CleanupSimulatorsViewModel(
            cleanupService: cleanupService,
            deviceManager: deviceManager
        )

        viewModel.refreshCleanupCandidates()
        try await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.cleanupCandidateGroups.map(\.title) == ["iOS 18.5", "iOS 17.4"])
        #expect(viewModel.cleanupCandidateGroups[0].candidates == [latestCandidate])
        #expect(viewModel.cleanupCandidateGroups[1].candidates == [firstOlderCandidate, secondOlderCandidate])
    }

    @Test("delete all cleanup candidates removes every candidate")
    func deleteAllCleanupCandidatesRemovesEveryCandidate() async throws {
        let deviceManager = MockDeviceManager()
        let cleanupService = MockSimulatorCleanupService()
        let firstCandidate = makeCandidate(id: "bulk-1", osVersion: "iOS 18.5")
        let secondCandidate = makeCandidate(id: "bulk-2", osVersion: "iOS 17.4")

        await cleanupService.setCleanupCandidates([firstCandidate, secondCandidate])

        let viewModel = CleanupSimulatorsViewModel(
            cleanupService: cleanupService,
            deviceManager: deviceManager
        )

        viewModel.refreshCleanupCandidates()
        try await Task.sleep(for: .milliseconds(50))
        viewModel.deleteAllCleanupCandidates()
        try await Task.sleep(for: .milliseconds(100))

        #expect(deviceManager.resetAndLoadDevicesCalled)
        #expect(viewModel.cleanupCandidates.isEmpty)
        #expect(await cleanupService.deletedCandidateIDs == [firstCandidate.id, secondCandidate.id])
    }

    @Test("delete all in group removes only that OS version")
    func deleteAllInGroupRemovesOnlySelectedVersion() async throws {
        let deviceManager = MockDeviceManager()
        let cleanupService = MockSimulatorCleanupService()
        let groupedCandidateA = makeCandidate(id: "group-1", osVersion: "iOS 18.5")
        let groupedCandidateB = makeCandidate(id: "group-2", osVersion: "iOS 18.5")
        let remainingCandidate = makeCandidate(id: "group-3", osVersion: "iOS 17.4")

        await cleanupService.setCleanupCandidates([groupedCandidateA, groupedCandidateB, remainingCandidate])

        let viewModel = CleanupSimulatorsViewModel(
            cleanupService: cleanupService,
            deviceManager: deviceManager
        )

        viewModel.refreshCleanupCandidates()
        try await Task.sleep(for: .milliseconds(50))

        guard let targetGroup = viewModel.cleanupCandidateGroups.first(where: { $0.title == "iOS 18.5" }) else {
            Issue.record("Expected an iOS 18.5 cleanup group")
            return
        }

        viewModel.deleteAll(in: targetGroup)
        try await Task.sleep(for: .milliseconds(100))

        #expect(deviceManager.resetAndLoadDevicesCalled)
        #expect(viewModel.cleanupCandidates == [remainingCandidate])
        #expect(await cleanupService.deletedCandidateIDs == [groupedCandidateA.id, groupedCandidateB.id])
    }

    private func makeCandidate(
        id: String,
        osVersion: String = "iOS 26.1",
        diskUsageBytes: Int64 = 1024,
        name: String = "Broken Simulator"
    ) -> SimulatorCleanupCandidate {
        SimulatorCleanupCandidate(
            id: id,
            name: name,
            udid: "E95A4AE1-04A0-4C9B-8CF2-EDDD2F6CE053",
            simulatorPlatform: .iPhone,
            osVersion: osVersion,
            lastBootedAt: nil,
            diskUsageBytes: diskUsageBytes,
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
