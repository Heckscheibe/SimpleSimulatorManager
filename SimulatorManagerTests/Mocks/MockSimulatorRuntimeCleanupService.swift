import Foundation
@testable import SimulatorManager
@testable import SimulatorCore

actor MockSimulatorRuntimeCleanupService: SimulatorRuntimeCleanupServing {
    struct MockError: Error, LocalizedError {
        let candidateID: String

        var errorDescription: String? {
            "Mock delete failure for \(candidateID)"
        }
    }

    private var candidates: [SimulatorRuntimeCleanupCandidate] = []
    private var checkedRuntimeCount = 0
    private var loadError: Error?
    private var failingCandidateIDs: Set<String> = []

    private(set) var deletedCandidateIDs: [String] = []
    private(set) var attemptedCandidateIDs: [String] = []

    func setCandidates(_ candidates: [SimulatorRuntimeCleanupCandidate], checked: Int? = nil) {
        self.candidates = candidates
        checkedRuntimeCount = checked ?? candidates.count
    }

    func setLoadError(_ error: Error?) {
        loadError = error
    }

    func setFailingCandidateIDs(_ ids: Set<String>) {
        failingCandidateIDs = ids
    }

    func loadRuntimeCleanupScan() async throws -> SimulatorRuntimeCleanupScan {
        await Task.yield()

        if let loadError {
            throw loadError
        }

        return SimulatorRuntimeCleanupScan(candidates: candidates, checkedRuntimeCount: checkedRuntimeCount)
    }

    func deleteRuntimeCandidate(_ candidate: SimulatorRuntimeCleanupCandidate) async throws {
        await Task.yield()

        attemptedCandidateIDs.append(candidate.id)

        if failingCandidateIDs.contains(candidate.id) {
            throw MockError(candidateID: candidate.id)
        }

        deletedCandidateIDs.append(candidate.id)
        candidates.removeAll { $0.id == candidate.id }
    }
}
