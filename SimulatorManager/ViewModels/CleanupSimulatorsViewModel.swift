import Foundation
import Observation
import os
import SimulatorCore

@MainActor
@Observable
final class CleanupSimulatorsViewModel {
    struct CandidateGroup: Identifiable, Equatable {
        let title: String
        let candidates: [SimulatorCleanupCandidate]

        var id: String {
            title
        }

        var count: Int {
            candidates.count
        }
    }

    var cleanupCandidates: [SimulatorCleanupCandidate] = []
    /// How many simulators the last successful scan examined, or `nil` when it has not run or
    /// cannot say. It is what turns an empty list into "nothing wrong" rather than "no idea".
    var checkedSimulatorCount: Int?
    var errorMessage: String?
    var isLoadingCleanupCandidates = false
    var deletingCandidateIDs = Set<String>()

    @ObservationIgnored private var hasLoadedCleanupCandidates = false
    @ObservationIgnored private var rescanRequested = false
    @ObservationIgnored private let cleanupService: SimulatorCleanupServing
    @ObservationIgnored private let deviceManager: DeviceManaging
    @ObservationIgnored private let destructiveActionConfirmer: DestructiveActionConfirming
    @ObservationIgnored private let deletionBatch = CleanupBatch<CleanupSimulatorsViewModel, SimulatorCleanupCandidate>(
        reservedIDs: \.deletingCandidateIDs,
        listedCandidates: \.cleanupCandidates,
        errorMessage: \.errorMessage,
        logLabel: "Cleanup"
    )

    init(
        cleanupService: SimulatorCleanupServing,
        deviceManager: DeviceManaging,
        destructiveActionConfirmer: DestructiveActionConfirming = AlertDestructiveActionConfirmer()
    ) {
        self.cleanupService = cleanupService
        self.deviceManager = deviceManager
        self.destructiveActionConfirmer = destructiveActionConfirmer
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

    var emptyStateText: String {
        guard let checkedSimulatorCount else {
            return "No invalid simulators found"
        }

        return "No invalid simulators found (\(checkedSimulatorCount) checked)"
    }

    var cleanupCandidateGroups: [CandidateGroup] {
        let groupedCandidates = Dictionary(grouping: cleanupCandidates, by: \.versionGroupTitle)

        return groupedCandidates
            .map { title, candidates in
                CandidateGroup(
                    title: title,
                    candidates: candidates.sorted(by: compareCandidates)
                )
            }
            .sorted(by: compareGroups)
    }

    func loadCleanupCandidatesIfNeeded() {
        guard !hasLoadedCleanupCandidates else {
            os_log("Cleanup scan skipped because candidates were already loaded")
            return
        }

        os_log("Cleanup scan requested for first load")
        refreshCleanupCandidates()
    }

    /// For a change made elsewhere that alters which simulators qualify, such as removing a runtime.
    /// Does nothing before the list was ever opened — the first open scans anyway — and, while a
    /// scan is running, asks for another once it ends, because that scan may have read the old state.
    func rescanAfterExternalChange() {
        if isLoadingCleanupCandidates {
            rescanRequested = true
        } else if hasLoadedCleanupCandidates {
            refreshCleanupCandidates()
        }
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
                if rescanRequested {
                    rescanRequested = false
                    refreshCleanupCandidates()
                }
                os_log(
                    "Cleanup scan finished. candidates=%{public}ld errorPresent=%{public}@",
                    cleanupCandidates.count,
                    String(errorMessage != nil)
                )
            }

            do {
                let scan = try await cleanupService.loadCleanupScan()
                cleanupCandidates = scan.candidates
                checkedSimulatorCount = scan.checkedSimulatorCount
                os_log("Cleanup scan loaded %{public}ld candidates", cleanupCandidates.count)
            } catch {
                cleanupCandidates = []
                checkedSimulatorCount = nil
                errorMessage = error.localizedDescription
                os_log("Cleanup scan failed: %{public}@", error.localizedDescription)
            }
        }
    }

    func delete(_ candidate: SimulatorCleanupCandidate) {
        delete(candidates: [candidate], scopeDescription: "candidate \(candidate.id)")
    }

    func deleteAllCleanupCandidates() {
        delete(candidates: cleanupCandidates, scopeDescription: "all cleanup candidates")
    }

    func deleteAll(in group: CandidateGroup) {
        delete(candidates: group.candidates, scopeDescription: "group \(group.title)")
    }

    func isDeleting(_ candidate: SimulatorCleanupCandidate) -> Bool {
        deletingCandidateIDs.contains(candidate.id)
    }

    func isDeleting(_ group: CandidateGroup) -> Bool {
        group.candidates.contains { deletingCandidateIDs.contains($0.id) }
    }

    private func delete(candidates: [SimulatorCleanupCandidate], scopeDescription: String) {
        let candidatesToDelete = deletionBatch.reserve(candidates, on: self)

        guard !candidatesToDelete.isEmpty else {
            os_log("Cleanup delete ignored because no candidates were available for %{public}@", scopeDescription)
            return
        }

        // Confirm before anything is deleted: `simctl delete` cannot be undone, while orphaned
        // directories only move to the Trash and need no prompt. Count the reserved candidates
        // rather than the requested ones, so the prompt cannot name simulators that another
        // in-flight batch already claimed and this one will skip.
        let unrecoverableCount = candidatesToDelete.count(where: { candidate in
            if case .simctlDelete = candidate.deletionMethod {
                return true
            }

            return false
        })

        if unrecoverableCount > 0,
           !destructiveActionConfirmer.confirmPermanentSimulatorDeletion(simulatorCount: unrecoverableCount) {
            deletionBatch.release(candidatesToDelete, on: self)
            os_log("Cleanup delete cancelled by the user for %{public}@", scopeDescription)
            return
        }

        os_log(
            "Cleanup delete starting for %{public}@ count=%{public}ld",
            scopeDescription,
            candidatesToDelete.count
        )

        deletionBatch.run(
            candidatesToDelete,
            on: self,
            delete: { [cleanupService] candidate in
                try await cleanupService.deleteCleanupCandidate(candidate)
            },
            afterDeletions: { [deviceManager] in
                await deviceManager.resetAndLoadDevices()
                os_log("Cleanup delete triggered device reload")
            },
            rescan: { [self] in
                let scan = try await cleanupService.loadCleanupScan()
                cleanupCandidates = scan.candidates
                checkedSimulatorCount = scan.checkedSimulatorCount
                os_log("Cleanup delete refreshed candidate list to %{public}ld items", cleanupCandidates.count)
            }
        )
    }

    private func compareCandidates(lhs: SimulatorCleanupCandidate, rhs: SimulatorCleanupCandidate) -> Bool {
        if lhs.diskUsageBytes != rhs.diskUsageBytes {
            return (lhs.diskUsageBytes ?? 0) > (rhs.diskUsageBytes ?? 0)
        }

        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private func compareGroups(lhs: CandidateGroup, rhs: CandidateGroup) -> Bool {
        let leftComponents = lhs.candidates.first?.versionSortComponents ?? []
        let rightComponents = rhs.candidates.first?.versionSortComponents ?? []
        let maxCount = max(leftComponents.count, rightComponents.count)

        for index in 0 ..< maxCount {
            let leftValue = index < leftComponents.count ? leftComponents[index] : -1
            let rightValue = index < rightComponents.count ? rightComponents[index] : -1

            if leftValue != rightValue {
                return leftValue > rightValue
            }
        }

        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}
