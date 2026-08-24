import Foundation
import Testing
@testable import SimulatorManager

@MainActor
@Suite("CleanupSimulatorsViewModel Tests")
struct CleanupSimulatorsViewModelTests {
    @Test("refresh loads cleanup candidates")
    func refreshLoadsCleanupCandidates() async {
        let deviceManager = MockDeviceManager()
        let cleanupService = MockSimulatorCleanupService()
        let candidate = makeCandidate(id: "simctl-test")

        await cleanupService.setCleanupCandidates([candidate])

        let viewModel = makeViewModel(
            cleanupService: cleanupService,
            deviceManager: deviceManager,
            confirmer: MockDestructiveActionConfirmer()
        )

        viewModel.refreshCleanupCandidates()
        await waitForRefreshToFinish(viewModel)

        #expect(viewModel.cleanupCandidates == [candidate])
        #expect(viewModel.errorMessage == nil)
        #expect(!viewModel.isLoadingCleanupCandidates)
    }

    @Test("delete removes candidate and refreshes devices")
    func deleteRemovesCandidateAndRefreshesDevices() async {
        let deviceManager = MockDeviceManager()
        let cleanupService = MockSimulatorCleanupService()
        let candidate = makeCandidate(id: "orphan-test")

        await cleanupService.setCleanupCandidates([candidate])

        let viewModel = makeViewModel(
            cleanupService: cleanupService,
            deviceManager: deviceManager,
            confirmer: MockDestructiveActionConfirmer()
        )

        viewModel.refreshCleanupCandidates()
        await waitForRefreshToFinish(viewModel)
        viewModel.delete(candidate)
        await waitForDeletionsToFinish(viewModel)

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

        let viewModel = makeViewModel(
            cleanupService: cleanupService,
            deviceManager: deviceManager,
            confirmer: MockDestructiveActionConfirmer()
        )

        viewModel.refreshCleanupCandidates()
        await waitForRefreshToFinish(viewModel)

        // `#require` before indexing: `#expect` records a failure and carries on, so an unexpected
        // group count would reach the subscripts below and trap the whole test host instead of
        // failing this one test.
        let groups = viewModel.cleanupCandidateGroups
        try #require(groups.count == 2)

        #expect(groups.map(\.title) == ["iOS 18.5", "iOS 17.4"])
        #expect(groups[0].candidates == [latestCandidate])
        #expect(groups[1].candidates == [firstOlderCandidate, secondOlderCandidate])
    }

    @Test("delete all cleanup candidates removes every candidate")
    func deleteAllCleanupCandidatesRemovesEveryCandidate() async {
        let deviceManager = MockDeviceManager()
        let cleanupService = MockSimulatorCleanupService()
        let firstCandidate = makeCandidate(id: "bulk-1", osVersion: "iOS 18.5")
        let secondCandidate = makeCandidate(id: "bulk-2", osVersion: "iOS 17.4")

        await cleanupService.setCleanupCandidates([firstCandidate, secondCandidate])

        let viewModel = makeViewModel(
            cleanupService: cleanupService,
            deviceManager: deviceManager,
            confirmer: MockDestructiveActionConfirmer()
        )

        viewModel.refreshCleanupCandidates()
        await waitForRefreshToFinish(viewModel)
        viewModel.deleteAllCleanupCandidates()
        await waitForDeletionsToFinish(viewModel)

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

        let viewModel = makeViewModel(
            cleanupService: cleanupService,
            deviceManager: deviceManager,
            confirmer: MockDestructiveActionConfirmer()
        )

        viewModel.refreshCleanupCandidates()
        await waitForRefreshToFinish(viewModel)

        let targetGroup = try #require(
            viewModel.cleanupCandidateGroups.first(where: { $0.title == "iOS 18.5" }),
            "Expected an iOS 18.5 cleanup group"
        )

        viewModel.deleteAll(in: targetGroup)
        await waitForDeletionsToFinish(viewModel)

        #expect(deviceManager.resetAndLoadDevicesCalled)
        #expect(viewModel.cleanupCandidates == [remainingCandidate])
        #expect(await cleanupService.deletedCandidateIDs == [groupedCandidateA.id, groupedCandidateB.id])
    }

    // MARK: - Partial failure handling

    @Test("A failing deletion does not abort the rest of the batch")
    func deleteContinuesAfterFailure() async {
        let deviceManager = MockDeviceManager()
        let cleanupService = MockSimulatorCleanupService()
        let confirmer = MockDestructiveActionConfirmer()
        let firstCandidate = makeCandidate(id: "batch-1")
        let failingCandidate = makeCandidate(id: "batch-2", name: "Stubborn Simulator")
        let lastCandidate = makeCandidate(id: "batch-3")

        await cleanupService.setCleanupCandidates([firstCandidate, failingCandidate, lastCandidate])
        await cleanupService.setFailingCandidateIDs([failingCandidate.id])

        let viewModel = makeViewModel(
            cleanupService: cleanupService,
            deviceManager: deviceManager,
            confirmer: confirmer
        )

        viewModel.refreshCleanupCandidates()
        await waitForRefreshToFinish(viewModel)
        viewModel.deleteAllCleanupCandidates()
        await waitForDeletionsToFinish(viewModel)

        // Every candidate is attempted, not just the ones before the failure.
        #expect(await cleanupService.attemptedCandidateIDs == [firstCandidate.id, failingCandidate.id, lastCandidate.id])
        #expect(await cleanupService.deletedCandidateIDs == [firstCandidate.id, lastCandidate.id])
    }

    @Test("A failing deletion still refreshes devices and the candidate list")
    func deleteRefreshesEvenWhenACandidateFails() async {
        let deviceManager = MockDeviceManager()
        let cleanupService = MockSimulatorCleanupService()
        let confirmer = MockDestructiveActionConfirmer()
        let succeedingCandidate = makeCandidate(id: "refresh-1")
        let failingCandidate = makeCandidate(id: "refresh-2", name: "Stubborn Simulator")

        await cleanupService.setCleanupCandidates([succeedingCandidate, failingCandidate])
        await cleanupService.setFailingCandidateIDs([failingCandidate.id])

        let viewModel = makeViewModel(
            cleanupService: cleanupService,
            deviceManager: deviceManager,
            confirmer: confirmer
        )

        viewModel.refreshCleanupCandidates()
        await waitForRefreshToFinish(viewModel)
        viewModel.deleteAllCleanupCandidates()
        await waitForDeletionsToFinish(viewModel)

        // The successful deletion must not linger in the UI, and the device list has to be reloaded
        // even though the batch reported an error.
        #expect(deviceManager.resetAndLoadDevicesCalled)
        #expect(viewModel.cleanupCandidates == [failingCandidate])
        #expect(viewModel.errorMessage?.contains("Stubborn Simulator") == true)
        #expect(viewModel.deletingCandidateIDs.isEmpty)
    }

    // MARK: - Confirmation of irreversible deletions

    @Test("Declining the confirmation deletes nothing")
    func declinedConfirmationCancelsDeletion() async {
        let deviceManager = MockDeviceManager()
        let cleanupService = MockSimulatorCleanupService()
        let confirmer = MockDestructiveActionConfirmer()
        confirmer.shouldConfirm = false
        let candidate = makeCandidate(id: "simctl-cancel")

        await cleanupService.setCleanupCandidates([candidate])

        let viewModel = makeViewModel(
            cleanupService: cleanupService,
            deviceManager: deviceManager,
            confirmer: confirmer
        )

        viewModel.refreshCleanupCandidates()
        await waitForRefreshToFinish(viewModel)
        viewModel.delete(candidate)
        await waitForDeletionsToFinish(viewModel)

        #expect(confirmer.confirmedSimulatorCounts == [1])
        #expect(await cleanupService.attemptedCandidateIDs.isEmpty)
        #expect(!deviceManager.resetAndLoadDevicesCalled)
        #expect(viewModel.cleanupCandidates == [candidate])
        #expect(viewModel.deletingCandidateIDs.isEmpty)
    }

    @Test("Only irreversible simctl deletions are counted in the confirmation")
    func confirmationCountsOnlyIrreversibleCandidates() async {
        let deviceManager = MockDeviceManager()
        let cleanupService = MockSimulatorCleanupService()
        let confirmer = MockDestructiveActionConfirmer()
        let simctlCandidate = makeCandidate(id: "simctl-mixed")
        let orphanCandidate = makeOrphanCandidate(id: "orphan-mixed")

        await cleanupService.setCleanupCandidates([simctlCandidate, orphanCandidate])

        let viewModel = makeViewModel(
            cleanupService: cleanupService,
            deviceManager: deviceManager,
            confirmer: confirmer
        )

        viewModel.refreshCleanupCandidates()
        await waitForRefreshToFinish(viewModel)
        viewModel.deleteAllCleanupCandidates()
        await waitForDeletionsToFinish(viewModel)

        // Only the simctl candidate is unrecoverable; the orphaned directory goes to the Trash.
        #expect(confirmer.confirmedSimulatorCounts == [1])
        #expect(await cleanupService.deletedCandidateIDs.count == 2)
    }

    @Test("Deleting only trashable directories asks for no confirmation")
    func trashOnlyDeletionSkipsConfirmation() async {
        let deviceManager = MockDeviceManager()
        let cleanupService = MockSimulatorCleanupService()
        let confirmer = MockDestructiveActionConfirmer()
        let orphanCandidate = makeOrphanCandidate(id: "orphan-only")

        await cleanupService.setCleanupCandidates([orphanCandidate])

        let viewModel = makeViewModel(
            cleanupService: cleanupService,
            deviceManager: deviceManager,
            confirmer: confirmer
        )

        viewModel.refreshCleanupCandidates()
        await waitForRefreshToFinish(viewModel)
        viewModel.delete(orphanCandidate)
        await waitForDeletionsToFinish(viewModel)

        #expect(!confirmer.wasAsked)
        #expect(await cleanupService.deletedCandidateIDs == [orphanCandidate.id])
    }

    // MARK: - Waiting for asynchronous work

    /// `refreshCleanupCandidates()` raises this flag synchronously and lowers it in the refresh
    /// task's `defer`, which makes it an exact completion signal for a scan.
    private func waitForRefreshToFinish(_ viewModel: CleanupSimulatorsViewModel) async {
        await waitUntil { !viewModel.isLoadingCleanupCandidates }
    }

    /// The delete entry points reserve their candidate IDs synchronously and release them in the
    /// deletion task's `defer` — after the device reload and the candidate re-fetch — so an empty
    /// set means the whole batch is done, not just the `simctl` calls.
    private func waitForDeletionsToFinish(_ viewModel: CleanupSimulatorsViewModel) async {
        await waitUntil { viewModel.deletingCandidateIDs.isEmpty }
    }

    // MARK: - Helpers

    private func makeViewModel(
        cleanupService: MockSimulatorCleanupService,
        deviceManager: MockDeviceManager,
        confirmer: MockDestructiveActionConfirmer
    ) -> CleanupSimulatorsViewModel {
        CleanupSimulatorsViewModel(
            cleanupService: cleanupService,
            deviceManager: deviceManager,
            destructiveActionConfirmer: confirmer
        )
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

    private func makeOrphanCandidate(
        id: String,
        osVersion: String = "iOS 26.1",
        name: String = "Orphaned Directory"
    ) -> SimulatorCleanupCandidate {
        SimulatorCleanupCandidate(
            id: id,
            name: name,
            udid: "5D91F5D6-6D4A-4D94-8B44-2926AE8E7C10",
            simulatorPlatform: .iPhone,
            osVersion: osVersion,
            lastBootedAt: nil,
            diskUsageBytes: 2048,
            reasons: [.orphanedDirectory],
            detailMessage: nil,
            deletionMethod: .trashDirectory(URL(fileURLWithPath: "/tmp/5D91F5D6-6D4A-4D94-8B44-2926AE8E7C10"))
        )
    }
}

private extension MockSimulatorCleanupService {
    func setCleanupCandidates(_ cleanupCandidates: [SimulatorCleanupCandidate]) {
        self.cleanupCandidates = cleanupCandidates
    }

    func setFailingCandidateIDs(_ failingCandidateIDs: Set<String>) {
        self.failingCandidateIDs = failingCandidateIDs
    }
}
