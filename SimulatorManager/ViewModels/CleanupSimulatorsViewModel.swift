import Foundation
import Observation
import os

@MainActor
@Observable
final class CleanupSimulatorsViewModel {
    var cleanupCandidates: [SimulatorCleanupCandidate] = []
    var errorMessage: String?
    var isLoadingCleanupCandidates = false
    var deletingCandidateIDs = Set<String>()

    @ObservationIgnored private var hasLoadedCleanupCandidates = false
    @ObservationIgnored private let cleanupService: SimulatorCleanupServing
    @ObservationIgnored private let deviceManager: DeviceManaging

    init(
        cleanupService: SimulatorCleanupServing,
        deviceManager: DeviceManaging
    ) {
        self.cleanupService = cleanupService
        self.deviceManager = deviceManager
    }

    var cleanupButtonText: String {
        if isLoadingCleanupCandidates {
            return "Scanning Cleanup…"
        }

        if !deletingCandidateIDs.isEmpty {
            return "Cleaning Up…"
        }

        guard !cleanupCandidates.isEmpty else {
            return "Cleanup Simulators"
        }

        return "Cleanup Simulators (\(cleanupCandidates.count))"
    }

    var cleanupButtonIcon: String {
        if isLoadingCleanupCandidates || !deletingCandidateIDs.isEmpty {
            return "hourglass"
        }

        return cleanupCandidates.isEmpty ? "trash.slash" : "exclamationmark.triangle"
    }

    func loadCleanupCandidatesIfNeeded() {
        guard !hasLoadedCleanupCandidates else {
            os_log("Cleanup scan skipped because candidates were already loaded")
            return
        }

        os_log("Cleanup scan requested for first load")
        refreshCleanupCandidates()
    }

    func refreshCleanupCandidates() {
        guard !isLoadingCleanupCandidates else {
            os_log("Cleanup scan request ignored because a scan is already in progress")
            return
        }

        os_log("Cleanup scan starting")
        errorMessage = nil
        isLoadingCleanupCandidates = true

        Task {
            defer {
                isLoadingCleanupCandidates = false
                hasLoadedCleanupCandidates = true
                os_log(
                    "Cleanup scan finished. candidates=%{public}ld errorPresent=%{public}@",
                    cleanupCandidates.count,
                    String(errorMessage != nil)
                )
            }

            do {
                cleanupCandidates = try await cleanupService.loadCleanupCandidates()
                os_log("Cleanup scan loaded %{public}ld candidates", cleanupCandidates.count)
            } catch {
                cleanupCandidates = []
                errorMessage = error.localizedDescription
                os_log("Cleanup scan failed: %{public}@", error.localizedDescription)
            }
        }
    }

    func delete(_ candidate: SimulatorCleanupCandidate) {
        guard deletingCandidateIDs.insert(candidate.id).inserted else {
            os_log("Cleanup delete ignored because candidate %{public}@ is already being deleted", candidate.id)
            return
        }

        os_log("Cleanup delete starting for candidate %{public}@ (%{public}@)", candidate.id, candidate.name)
        errorMessage = nil

        Task {
            defer {
                deletingCandidateIDs.remove(candidate.id)
                os_log("Cleanup delete finished for candidate %{public}@", candidate.id)
            }

            do {
                try await cleanupService.deleteCleanupCandidate(candidate)
                os_log("Cleanup delete succeeded for candidate %{public}@", candidate.id)
                deviceManager.resetAndLoadDevices()
                os_log("Cleanup delete triggered device reload")
                cleanupCandidates = try await cleanupService.loadCleanupCandidates()
                os_log("Cleanup delete refreshed candidate list to %{public}ld items", cleanupCandidates.count)
            } catch {
                errorMessage = error.localizedDescription
                os_log("Cleanup delete failed for candidate %{public}@: %{public}@", candidate.id, error.localizedDescription)
            }
        }
    }

    func isDeleting(_ candidate: SimulatorCleanupCandidate) -> Bool {
        deletingCandidateIDs.contains(candidate.id)
    }
}
