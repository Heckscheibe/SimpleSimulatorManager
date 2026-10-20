// The protocol requirement is async; the mock answers at once.
// swiftlint:disable async_without_await

import Foundation
@testable import SimulatorCore
@testable import SimulatorManager

/// Records where each save was asked to go and answers from a queue of results, reporting a little
/// progress first as the real capture does.
final class MockAppSnapshotSaver: AppSnapshotSaving, @unchecked Sendable {
    struct Call: Equatable {
        let directoryURL: URL
        let includeCaches: Bool
    }

    private let lock = NSLock()
    private var results: [Result<URL, any Error>]
    private var recordedCalls: [Call] = []

    /// - Parameter results: One per expected save, in order. Once used up, every save succeeds.
    init(results: [Result<URL, any Error>] = []) {
        self.results = results
    }

    var calls: [Call] {
        lock.withLock { recordedCalls }
    }

    func saveSnapshot(
        of target: AppSnapshotTarget,
        into directoryURL: URL,
        includeCaches: Bool,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> URL {
        let result: Result<URL, any Error> = lock.withLock {
            recordedCalls.append(Call(directoryURL: directoryURL, includeCaches: includeCaches))

            return results.isEmpty
                ? .success(directoryURL.appendingPathComponent("saved", isDirectory: true))
                : results.removeFirst()
        }

        progress?(0.5)

        return try result.get()
    }
}
