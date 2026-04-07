import Foundation
import Observation
import os

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
        let candidatesToDelete = reserveDeletionIDs(for: candidates)

        guard !candidatesToDelete.isEmpty else {
            os_log("Cleanup delete ignored because no candidates were available for %{public}@", scopeDescription)
            return
        }

        os_log(
            "Cleanup delete starting for %{public}@ count=%{public}ld",
            scopeDescription,
            candidatesToDelete.count
        )
        errorMessage = nil

        Task {
            defer {
                for candidate in candidatesToDelete {
                    deletingCandidateIDs.remove(candidate.id)
                }
                os_log(
                    "Cleanup delete finished for %{public}@ count=%{public}ld",
                    scopeDescription,
                    candidatesToDelete.count
                )
            }

            do {
                for candidate in candidatesToDelete {
                    try await cleanupService.deleteCleanupCandidate(candidate)
                    os_log("Cleanup delete succeeded for candidate %{public}@", candidate.id)
                }

                deviceManager.resetAndLoadDevices()
                os_log("Cleanup delete triggered device reload")
                cleanupCandidates = try await cleanupService.loadCleanupCandidates()
                os_log("Cleanup delete refreshed candidate list to %{public}ld items", cleanupCandidates.count)
            } catch {
                errorMessage = error.localizedDescription
                os_log("Cleanup delete failed for %{public}@: %{public}@", scopeDescription, error.localizedDescription)
            }
        }
    }

    private func reserveDeletionIDs(for candidates: [SimulatorCleanupCandidate]) -> [SimulatorCleanupCandidate] {
        var candidatesToDelete: [SimulatorCleanupCandidate] = []

        for candidate in candidates where deletingCandidateIDs.insert(candidate.id).inserted {
            candidatesToDelete.append(candidate)
        }

        return candidatesToDelete
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
