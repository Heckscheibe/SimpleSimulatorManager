import Foundation
@testable import SimulatorManager

actor MockSimulatorCleanupService: SimulatorCleanupServing {
    var cleanupCandidates: [SimulatorCleanupCandidate] = []
    var loadError: Error?
    var deleteError: Error?

    private(set) var deletedCandidateIDs: [String] = []

    func loadCleanupCandidates() async throws -> [SimulatorCleanupCandidate] {
        await Task.yield()

        if let loadError {
            throw loadError
        }

        return cleanupCandidates
    }

    func deleteCleanupCandidate(_ candidate: SimulatorCleanupCandidate) async throws {
        await Task.yield()

        if let deleteError {
            throw deleteError
        }

        deletedCandidateIDs.append(candidate.id)
        cleanupCandidates.removeAll { $0.id == candidate.id }
    }
}
