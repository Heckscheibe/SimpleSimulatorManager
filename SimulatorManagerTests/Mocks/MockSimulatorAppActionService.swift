import Foundation
@testable import SimulatorManager

/// Records terminate calls so a restore can be checked for stopping the app before it copies,
/// without a booted simulator.
final class MockSimulatorAppActionService: SimulatorAppActionServing, @unchecked Sendable {
    private let lock = NSLock()
    private var terminatedApps: [(bundleIdentifier: String, deviceUdid: String)] = []
    private var errorToThrow: Error?
    /// Set by ``terminateApp(bundleIdentifier:deviceUdid:)`` and read by a capture stub, so a test
    /// can prove the terminate happened before anything was copied.
    private(set) var didTerminate = false

    var terminateCallCount: Int {
        lock.withLock { terminatedApps.count }
    }

    var lastTerminatedApp: (bundleIdentifier: String, deviceUdid: String)? {
        lock.withLock { terminatedApps.last }
    }

    func setError(_ error: Error?) {
        lock.withLock { errorToThrow = error }
    }

    func terminateApp(bundleIdentifier: String, deviceUdid: String) async throws {
        // The real service suspends here; yielding keeps the mock a genuine suspension point so
        // callers are exercised the same way.
        await Task.yield()

        let error: Error? = lock.withLock {
            terminatedApps.append((bundleIdentifier, deviceUdid))
            didTerminate = true

            return errorToThrow
        }

        if let error {
            throw error
        }
    }
}
