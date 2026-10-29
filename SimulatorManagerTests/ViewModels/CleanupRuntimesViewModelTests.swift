import Foundation
import Testing
@testable import SimulatorManager
@testable import SimulatorCore

@MainActor
@Suite("CleanupRuntimesViewModel Tests")
struct CleanupRuntimesViewModelTests {
    @Test("refresh loads candidates and remembers how many runtimes were checked")
    func refreshLoadsCandidates() async {
        let service = MockSimulatorRuntimeCleanupService()
        let candidate = makeCandidate(id: "a")
        await service.setCandidates([candidate], checked: 7)
        let viewModel = makeViewModel(service: service)

        viewModel.refresh()
        await waitUntil { !viewModel.isLoading }

        #expect(viewModel.candidates == [candidate])
        #expect(viewModel.checkedRuntimeCount == 7)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("an empty scan says how many runtimes were checked")
    func emptyStateNamesTheCount() async {
        let service = MockSimulatorRuntimeCleanupService()
        await service.setCandidates([], checked: 7)
        let viewModel = makeViewModel(service: service)

        #expect(viewModel.emptyStateText == "No stale runtimes found")

        viewModel.refresh()
        await waitUntil { !viewModel.isLoading }

        #expect(viewModel.emptyStateText == "No stale runtimes found (7 checked)")
    }

    @Test("a failing scan reports the error and clears the list")
    func failingScan() async {
        let service = MockSimulatorRuntimeCleanupService()
        await service.setLoadError(MockSimulatorRuntimeCleanupService.MockError(candidateID: "scan"))
        let viewModel = makeViewModel(service: service)

        viewModel.refresh()
        await waitUntil { !viewModel.isLoading }

        #expect(viewModel.candidates.isEmpty)
        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.checkedRuntimeCount == nil)
    }

    @Test("button text carries the count and the reclaimable size")
    func buttonText() async {
        let service = MockSimulatorRuntimeCleanupService()
        await service.setCandidates([
            makeCandidate(id: "a", sizeBytes: 1_000_000_000),
            makeCandidate(id: "b", sizeBytes: 2_000_000_000)
        ])
        let viewModel = makeViewModel(service: service)

        #expect(viewModel.buttonText == "Cleanup Runtimes")

        viewModel.refresh()
        await waitUntil { !viewModel.isLoading }

        #expect(viewModel.totalReclaimableBytes == 3_000_000_000)
        #expect(viewModel.buttonText.hasPrefix("Cleanup Runtimes (2, "))
    }

    @Test("delete confirms, removes the runtime, reloads devices and tells the owner")
    func deleteConfirmsAndReloads() async {
        let service = MockSimulatorRuntimeCleanupService()
        let deviceManager = MockDeviceManager()
        let confirmer = MockDestructiveActionConfirmer()
        let candidate = makeCandidate(id: "a", sizeBytes: 5, affectedSimulators: 3)
        await service.setCandidates([candidate])
        var notified = 0
        let viewModel = makeViewModel(service: service, deviceManager: deviceManager, confirmer: confirmer) {
            notified += 1
        }

        viewModel.refresh()
        await waitUntil { !viewModel.isLoading }
        viewModel.delete(candidate)
        await waitUntil { viewModel.deletingCandidateIDs.isEmpty }

        #expect(confirmer.confirmedRuntimeRequests.map(\.runtimeCount) == [1])
        #expect(confirmer.confirmedRuntimeRequests.map(\.simulatorCount) == [3])
        #expect(confirmer.confirmedRuntimeRequests.map(\.totalBytes) == [5])
        #expect(await service.deletedCandidateIDs == [candidate.id])
        #expect(deviceManager.resetAndLoadDevicesCalled)
        #expect(notified == 1)
        #expect(viewModel.candidates.isEmpty)
    }

    @Test("declining the confirmation deletes nothing and releases the reservation")
    func decliningDeletesNothing() async {
        let service = MockSimulatorRuntimeCleanupService()
        let confirmer = MockDestructiveActionConfirmer()
        confirmer.shouldConfirm = false
        let candidate = makeCandidate(id: "a")
        await service.setCandidates([candidate])
        let viewModel = makeViewModel(service: service, confirmer: confirmer)

        viewModel.refresh()
        await waitUntil { !viewModel.isLoading }
        viewModel.delete(candidate)

        #expect(viewModel.deletingCandidateIDs.isEmpty)
        #expect(await service.attemptedCandidateIDs.isEmpty)
        #expect(viewModel.candidates == [candidate])
    }

    @Test("one failing runtime does not stop the batch, and is reported")
    func partialFailure() async {
        let service = MockSimulatorRuntimeCleanupService()
        let good = makeCandidate(id: "good")
        let bad = makeCandidate(id: "bad")
        await service.setCandidates([bad, good])
        await service.setFailingCandidateIDs([bad.id])
        let viewModel = makeViewModel(service: service)

        viewModel.refresh()
        await waitUntil { !viewModel.isLoading }
        viewModel.deleteAll()
        await waitUntil { viewModel.deletingCandidateIDs.isEmpty }

        #expect(await service.deletedCandidateIDs == [good.id])
        #expect(viewModel.errorMessage?.contains(bad.name) == true)
        #expect(viewModel.candidates == [bad])
    }

    @Test("simulators on the same runtime are counted once in the confirmation")
    func sharedRuntimeCountedOnce() async {
        let service = MockSimulatorRuntimeCleanupService()
        let confirmer = MockDestructiveActionConfirmer()
        let first = makeCandidate(id: "a", runtime: "rt", affectedSimulators: 4)
        let second = makeCandidate(id: "b", runtime: "rt", affectedSimulators: 4)
        await service.setCandidates([first, second])
        let viewModel = makeViewModel(service: service, confirmer: confirmer)

        viewModel.refresh()
        await waitUntil { !viewModel.isLoading }
        viewModel.deleteAll()
        await waitUntil { viewModel.deletingCandidateIDs.isEmpty }

        #expect(confirmer.confirmedRuntimeRequests.map(\.simulatorCount) == [4])
    }

    @Test("running simulators are passed to the confirmation, once per runtime")
    func bootedSimulatorsReachTheConfirmation() async {
        let service = MockSimulatorRuntimeCleanupService()
        let confirmer = MockDestructiveActionConfirmer()
        let candidate = makeCandidate(id: "a", affectedSimulators: 3, bootedSimulators: 2)
        await service.setCandidates([candidate])
        let viewModel = makeViewModel(service: service, confirmer: confirmer)

        viewModel.refresh()
        await waitUntil { !viewModel.isLoading }
        viewModel.delete(candidate)
        await waitUntil { viewModel.deletingCandidateIDs.isEmpty }

        #expect(confirmer.confirmedRuntimeRequests.map(\.bootedSimulatorCount) == [2])
    }

    @Test("when the rescan after a deletion fails, the deleted runtime does not stay listed")
    func failedRescanDropsDeletedRuntimes() async {
        let service = MockSimulatorRuntimeCleanupService()
        let deleted = makeCandidate(id: "deleted")
        let kept = makeCandidate(id: "kept", runtime: "other")
        await service.setCandidates([deleted, kept])
        await service.setFailLoadsAfterDelete(true)
        let viewModel = makeViewModel(service: service)

        viewModel.refresh()
        await waitUntil { !viewModel.isLoading }
        viewModel.delete(deleted)
        await waitUntil { viewModel.deletingCandidateIDs.isEmpty }

        #expect(viewModel.candidates == [kept])
        #expect(viewModel.errorMessage != nil)
    }

    @Test("groups by platform")
    func groupsByPlatform() async throws {
        let service = MockSimulatorRuntimeCleanupService()
        await service.setCandidates([
            makeCandidate(id: "a", platform: "watchOS"),
            makeCandidate(id: "b", platform: "iOS"),
            makeCandidate(id: "c", platform: "iOS", version: "27.0")
        ])
        let viewModel = makeViewModel(service: service)

        viewModel.refresh()
        await waitUntil { !viewModel.isLoading }

        let groups = viewModel.candidateGroups
        try #require(groups.count == 2)
        #expect(groups.map(\.title) == ["iOS", "watchOS"])
        #expect(groups[0].candidates.map(\.id) == ["runtime-c", "runtime-b"])
    }

    // MARK: - Helpers

    private func makeViewModel(
        service: MockSimulatorRuntimeCleanupService,
        deviceManager: MockDeviceManager? = nil,
        confirmer: MockDestructiveActionConfirmer? = nil,
        didDelete: @escaping @MainActor () -> Void = {}
    ) -> CleanupRuntimesViewModel {
        CleanupRuntimesViewModel(
            cleanupService: service,
            deviceManager: deviceManager ?? MockDeviceManager(),
            destructiveActionConfirmer: confirmer ?? MockDestructiveActionConfirmer(),
            didDeleteRuntimes: didDelete
        )
    }

    private func makeCandidate(
        id: String,
        runtime: String? = nil,
        platform: String = "iOS",
        version: String = "26.4",
        sizeBytes: Int64? = 8_000_000_000,
        affectedSimulators: Int = 0,
        bootedSimulators: Int = 0
    ) -> SimulatorRuntimeCleanupCandidate {
        SimulatorRuntimeCleanupCandidate(
            imageIdentifier: id,
            runtimeIdentifier: runtime ?? "com.apple.CoreSimulator.SimRuntime.\(platform)-\(id)",
            platformName: platform,
            version: version,
            build: "23E\(id)",
            sizeBytes: sizeBytes,
            lastUsedAt: nil,
            reasons: [.unused],
            affectedSimulatorCount: affectedSimulators,
            bootedSimulatorCount: bootedSimulators,
            detailMessage: nil
        )
    }
}
