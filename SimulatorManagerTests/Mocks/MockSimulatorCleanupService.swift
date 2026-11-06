import Foundation
@testable import SimulatorManager
@testable import SimulatorCore

actor MockSimulatorCleanupService: SimulatorCleanupServing {
    struct MockError: Error, LocalizedError {
        let candidateID: String

        var errorDescription: String? {
            "Mock delete failure for \(candidateID)"
        }
    }

    var cleanupCandidates: [SimulatorCleanupCandidate] = []
    var loadError: Error?
    var deleteError: Error?
    /// Candidate IDs whose deletion should fail, so tests can exercise partial-failure batches.
    var failingCandidateIDs: Set<String> = []

    private(set) var deletedCandidateIDs: [String] = []
    private(set) var attemptedCandidateIDs: [String] = []
    private(set) var loadCount = 0

    func loadCleanupCandidates() async throws -> [SimulatorCleanupCandidate] {
        loadCount += 1
        await Task.yield()

        if let loadError {
            throw loadError
        }

        return cleanupCandidates
    }

    func deleteCleanupCandidate(_ candidate: SimulatorCleanupCandidate) async throws {
        await Task.yield()

        attemptedCandidateIDs.append(candidate.id)

        if let deleteError {
            throw deleteError
        }

        if failingCandidateIDs.contains(candidate.id) {
            throw MockError(candidateID: candidate.id)
        }

        deletedCandidateIDs.append(candidate.id)
        cleanupCandidates.removeAll { $0.id == candidate.id }
    }
}
