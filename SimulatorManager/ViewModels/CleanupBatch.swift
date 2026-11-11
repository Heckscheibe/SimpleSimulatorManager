import Foundation
import os
import SimulatorCore

/// A row a cleanup batch can delete: identified by a string, and named in a failure message.
protocol CleanupBatchCandidate: Identifiable, Sendable where ID == String {
    var name: String { get }
}

extension SimulatorCleanupCandidate: CleanupBatchCandidate {}
extension SimulatorRuntimeCleanupCandidate: CleanupBatchCandidate {}

/// The deletion mechanics ``CleanupSimulatorsViewModel`` and ``CleanupRuntimesViewModel`` share,
/// kept in one place so the two surfaces cannot drift apart again. It works on the owning view
/// model's own published state through key paths, so each view model keeps its own surface.
///
/// What it does *not* decide is whether to ask first and what to say: each view model confirms
/// between ``reserve(_:on:)`` and ``run(_:on:delete:afterDeletions:rescan:)``, and hands the
/// reservation back with ``release(_:on:)`` when the user declines.
@MainActor
struct CleanupBatch<Owner: AnyObject, Candidate: CleanupBatchCandidate> {
    /// The ids of candidates some batch is deleting right now.
    let reservedIDs: ReferenceWritableKeyPath<Owner, Set<String>>
    /// The candidate list the owner shows.
    let listedCandidates: ReferenceWritableKeyPath<Owner, [Candidate]>
    let errorMessage: ReferenceWritableKeyPath<Owner, String?>
    /// Prefix for log lines, so the two cleanup surfaces stay distinguishable.
    let logLabel: String

    /// Claims the requested candidates no other batch has claimed yet, and returns only those.
    /// Reserve before confirming, so a second click while the alert is up cannot queue the same
    /// candidate twice, and so a confirmation counts only what this batch will really delete.
    func reserve(_ requested: [Candidate], on owner: Owner) -> [Candidate] {
        var reserved: [Candidate] = []

        for candidate in requested where owner[keyPath: reservedIDs].insert(candidate.id).inserted {
            reserved.append(candidate)
        }

        return reserved
    }

    func release(_ reserved: [Candidate], on owner: Owner) {
        for candidate in reserved {
            owner[keyPath: reservedIDs].remove(candidate.id)
        }
    }

    /// Deletes the reserved candidates one by one, then lets the owner reload and rescan, and
    /// releases the reservation once all of that is done.
    ///
    /// - Parameters:
    ///   - afterDeletions: Runs once every candidate was attempted, whatever the outcome, because
    ///     whatever was removed changes what the rest of the app shows.
    ///   - rescan: Replaces the owner's list. If it throws, the candidates this batch deleted are
    ///     dropped from the list anyway and the error is shown.
    func run(
        _ reserved: [Candidate],
        on owner: Owner,
        delete: @escaping @MainActor (Candidate) async throws -> Void,
        afterDeletions: @escaping @MainActor () async -> Void,
        rescan: @escaping @MainActor () async throws -> Void
    ) {
        owner[keyPath: errorMessage] = nil

        Task {
            var failureMessages: [String] = []
            var deletedIDs = Set<String>()

            defer {
                release(reserved, on: owner)
                // Only ever *set* the message. Assigning nil on success would clear an error that
                // another still-running batch just reported for a candidate it could not remove,
                // leaving the user with no sign that anything failed.
                if !failureMessages.isEmpty {
                    owner[keyPath: errorMessage] = failureMessages.joined(separator: "\n")
                }
                os_log(
                    "%{public}@ delete finished count=%{public}ld failures=%{public}ld",
                    logLabel,
                    reserved.count,
                    failureMessages.count
                )
            }

            // Keep going after a failure instead of abandoning the batch: one candidate that
            // refuses to delete should not stop the rest, and the successful deletions still have
            // to be reflected in the UI.
            for candidate in reserved {
                do {
                    try await delete(candidate)
                    deletedIDs.insert(candidate.id)
                    os_log("%{public}@ delete succeeded for %{public}@", logLabel, candidate.id)
                } catch {
                    failureMessages.append("\(candidate.name): \(error.localizedDescription)")
                    os_log(
                        "%{public}@ delete failed for %{public}@: %{public}@",
                        logLabel,
                        candidate.id,
                        error.localizedDescription
                    )
                }
            }

            await afterDeletions()

            do {
                try await rescan()
            } catch {
                // The rescan failed, but the deletions did not: drop what was removed rather than
                // leave rows that offer to delete something already gone, which would only fail
                // again with a more confusing error.
                owner[keyPath: listedCandidates].removeAll { deletedIDs.contains($0.id) }
                failureMessages.append(error.localizedDescription)
                os_log("%{public}@ could not rescan after deleting: %{public}@", logLabel, error.localizedDescription)
            }
        }
    }
}
