import Foundation
import Observation
import os
import SimulatorCore

/// Drives the "Cleanup Runtimes" submenu. Mirrors ``CleanupSimulatorsViewModel`` deliberately —
/// same reservation of in-flight deletions, same continue-after-failure batches — so the two
/// cleanup surfaces behave alike. Every runtime deletion is permanent and confirmed first.
@MainActor
@Observable
final class CleanupRuntimesViewModel {
    struct CandidateGroup: Identifiable, Equatable {
        let title: String
        let candidates: [SimulatorRuntimeCleanupCandidate]

        var id: String {
            title
        }

        var count: Int {
            candidates.count
        }
    }

    var candidates: [SimulatorRuntimeCleanupCandidate] = []
    /// Runtime images the last successful scan examined; `nil` before any scan has finished.
    var checkedRuntimeCount: Int?
    var errorMessage: String?
    var isLoading = false
    var deletingCandidateIDs = Set<String>()

    @ObservationIgnored private var hasLoaded = false
    @ObservationIgnored private let cleanupService: SimulatorRuntimeCleanupServing
    @ObservationIgnored private let deviceManager: DeviceManaging
    @ObservationIgnored private let destructiveActionConfirmer: DestructiveActionConfirming
    /// Deleting a runtime changes which simulators are usable, so whoever shows the simulator
    /// cleanup list needs to look again.
    @ObservationIgnored private let didDeleteRuntimes: @MainActor () -> Void

    init(
        cleanupService: SimulatorRuntimeCleanupServing,
        deviceManager: DeviceManaging,
        destructiveActionConfirmer: DestructiveActionConfirming = AlertDestructiveActionConfirmer(),
        didDeleteRuntimes: @escaping @MainActor () -> Void = {}
    ) {
        self.cleanupService = cleanupService
        self.deviceManager = deviceManager
        self.destructiveActionConfirmer = destructiveActionConfirmer
        self.didDeleteRuntimes = didDeleteRuntimes
    }

    var totalReclaimableBytes: Int64 {
        candidates.compactMap(\.sizeBytes).reduce(0, +)
    }

    var buttonText: String {
        if isLoading {
            return "Scanning Runtimes…"
        }

        if !deletingCandidateIDs.isEmpty {
            return "Removing Runtimes…"
        }

        guard !candidates.isEmpty else {
            return "Cleanup Runtimes"
        }

        let size = ByteCountFormatter.string(fromByteCount: totalReclaimableBytes, countStyle: .file)
        return "Cleanup Runtimes (\(candidates.count), \(size))"
    }

    var buttonIcon: String {
        if isLoading || !deletingCandidateIDs.isEmpty {
            return "hourglass"
        }

        return candidates.isEmpty ? "externaldrive" : "externaldrive.badge.exclamationmark"
    }

    var emptyStateText: String {
        guard let checkedRuntimeCount else {
            return "No stale runtimes found"
        }

        return "No stale runtimes found (\(checkedRuntimeCount) checked)"
    }

    var candidateGroups: [CandidateGroup] {
        Dictionary(grouping: candidates, by: \.versionGroupTitle)
            .map { title, candidates in
                CandidateGroup(title: title, candidates: candidates.sorted(by: compareCandidates))
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func loadIfNeeded() {
        guard !hasLoaded else {
            return
        }

        refresh()
    }

    func refresh() {
        guard !isLoading else {
            return
        }

        errorMessage = nil
        isLoading = true

        Task {
            defer {
                isLoading = false
                hasLoaded = true
            }

            do {
                let scan = try await cleanupService.loadRuntimeCleanupScan()
                candidates = scan.candidates
                checkedRuntimeCount = scan.checkedRuntimeCount
                os_log("Runtime cleanup scan loaded %{public}ld candidates", scan.candidates.count)
            } catch {
                candidates = []
                checkedRuntimeCount = nil
                errorMessage = error.localizedDescription
                os_log("Runtime cleanup scan failed: %{public}@", error.localizedDescription)
            }
        }
    }

    func delete(_ candidate: SimulatorRuntimeCleanupCandidate) {
        delete(candidates: [candidate])
    }

    func deleteAll() {
        delete(candidates: candidates)
    }

    func deleteAll(in group: CandidateGroup) {
        delete(candidates: group.candidates)
    }

    func isDeleting(_ candidate: SimulatorRuntimeCleanupCandidate) -> Bool {
        deletingCandidateIDs.contains(candidate.id)
    }

    func isDeleting(_ group: CandidateGroup) -> Bool {
        group.candidates.contains { deletingCandidateIDs.contains($0.id) }
    }

    private func delete(candidates requested: [SimulatorRuntimeCleanupCandidate]) {
        // Reserve before confirming, so a second click while the alert is up cannot queue the same
        // runtime twice, and count only what this batch will really delete.
        var toDelete: [SimulatorRuntimeCleanupCandidate] = []
        for candidate in requested where deletingCandidateIDs.insert(candidate.id).inserted {
            toDelete.append(candidate)
        }

        guard !toDelete.isEmpty else {
            return
        }

        // Candidates sharing a runtime identifier strand the same simulators; count them once.
        let affectedSimulatorCount = Dictionary(grouping: toDelete, by: \.runtimeIdentifier)
            .values
            .map { $0.map(\.affectedSimulatorCount).max() ?? 0 }
            .reduce(0, +)
        let totalBytes = toDelete.compactMap(\.sizeBytes).reduce(0, +)

        guard destructiveActionConfirmer.confirmRuntimeDeletion(
            runtimeCount: toDelete.count,
            totalBytes: totalBytes,
            simulatorCount: affectedSimulatorCount
        ) else {
            for candidate in toDelete {
                deletingCandidateIDs.remove(candidate.id)
            }
            os_log("Runtime cleanup delete cancelled by the user")
            return
        }

        errorMessage = nil

        Task {
            var failureMessages: [String] = []

            defer {
                for candidate in toDelete {
                    deletingCandidateIDs.remove(candidate.id)
                }
                // Only ever set the message, so one batch cannot wipe another's failure.
                if !failureMessages.isEmpty {
                    errorMessage = failureMessages.joined(separator: "\n")
                }
            }

            for candidate in toDelete {
                do {
                    try await cleanupService.deleteRuntimeCandidate(candidate)
                    os_log("Runtime cleanup deleted %{public}@", candidate.id)
                } catch {
                    failureMessages.append("\(candidate.name): \(error.localizedDescription)")
                    os_log("Runtime cleanup failed for %{public}@: %{public}@", candidate.id, error.localizedDescription)
                }
            }

            // Whatever was removed changes which simulators are usable, whether or not the rest
            // of the batch succeeded.
            await deviceManager.resetAndLoadDevices()
            didDeleteRuntimes()

            do {
                let scan = try await cleanupService.loadRuntimeCleanupScan()
                candidates = scan.candidates
                checkedRuntimeCount = scan.checkedRuntimeCount
            } catch {
                failureMessages.append(error.localizedDescription)
            }
        }
    }

    private func compareCandidates(lhs: SimulatorRuntimeCleanupCandidate, rhs: SimulatorRuntimeCleanupCandidate) -> Bool {
        let left = lhs.versionSortComponents
        let right = rhs.versionSortComponents

        for index in 0 ..< max(left.count, right.count) {
            let leftValue = index < left.count ? left[index] : 0
            let rightValue = index < right.count ? right[index] : 0

            if leftValue != rightValue {
                return leftValue > rightValue
            }
        }

        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}
