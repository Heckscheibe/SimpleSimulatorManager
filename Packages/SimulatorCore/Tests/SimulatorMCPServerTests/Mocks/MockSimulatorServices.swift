import Combine
import Foundation
import SimulatorCore
import Synchronization

// The protocols are async and throwing; these stand-ins answer synchronously.
// swiftlint:disable async_without_await unneeded_throws_rethrows

struct MockServiceError: LocalizedError {
    var errorDescription: String? {
        "simctl failed"
    }
}

/// Records simctl-backed calls instead of running them, so no test touches a real simulator.
final class MockSimulatorResetService: SimulatorResetServing {
    enum Call: Equatable {
        case shutDownAndErase(udid: String)
        case shutDownAll
        case resetAll
        case shutDownAndResetAll
    }

    private let recordedCalls = Mutex<[Call]>([])
    private let shouldFail: Bool

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    var calls: [Call] {
        recordedCalls.withLock { $0 }
    }

    var didResetAllSimulators: AnyPublisher<Void, Never> {
        Empty().eraseToAnyPublisher()
    }

    func shutDownAndEraseSimulator(deviceUdid: String) async throws {
        try record(.shutDownAndErase(udid: deviceUdid))
    }

    func shutDownAllSimulators() async throws {
        try record(.shutDownAll)
    }

    func resetAllSimulators() async throws {
        try record(.resetAll)
    }

    func shutDownAndResetAllSimulators() async throws {
        try record(.shutDownAndResetAll)
    }

    private func record(_ call: Call) throws {
        if shouldFail {
            throw MockServiceError()
        }
        recordedCalls.withLock { $0.append(call) }
    }
}

/// Serves fixed candidates and records deletions instead of deleting anything.
final class MockSimulatorCleanupService: SimulatorCleanupServing {
    private let candidates: Mutex<[SimulatorCleanupCandidate]>
    private let deletedCandidates = Mutex<[SimulatorCleanupCandidate]>([])
    private let loadCount = Mutex(0)

    init(candidates: [SimulatorCleanupCandidate] = []) {
        self.candidates = Mutex(candidates)
    }

    var deleted: [SimulatorCleanupCandidate] {
        deletedCandidates.withLock { $0 }
    }

    var loads: Int {
        loadCount.withLock { $0 }
    }

    func loadCleanupCandidates() async throws -> [SimulatorCleanupCandidate] {
        loadCount.withLock { $0 += 1 }
        return candidates.withLock { $0 }
    }

    func deleteCleanupCandidate(_ candidate: SimulatorCleanupCandidate) async throws {
        deletedCandidates.withLock { $0.append(candidate) }
        candidates.withLock { $0.removeAll { $0.id == candidate.id } }
    }
}

// swiftlint:enable async_without_await unneeded_throws_rethrows
