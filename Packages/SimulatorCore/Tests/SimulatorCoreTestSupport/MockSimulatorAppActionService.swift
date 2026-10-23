import Foundation
import SimulatorCore

/// Records terminate calls so a capture or restore can be checked for stopping the app before it
/// copies, without a booted simulator.
public final class MockSimulatorAppActionService: SimulatorAppActionServing, @unchecked Sendable {
    private let lock = NSLock()
    private var terminatedApps: [(bundleIdentifier: String, deviceUdid: String)] = []
    private var errorToThrow: Error?
    /// Set by ``terminateApp(bundleIdentifier:deviceUdid:)`` and read by a capture stub, so a test
    /// can prove the terminate happened before anything was copied.
    public private(set) var didTerminate = false
    private var outcome: AppTerminationOutcome = .terminated

    public init() {}

    public var terminateCallCount: Int {
        lock.withLock { terminatedApps.count }
    }

    public var lastTerminatedApp: (bundleIdentifier: String, deviceUdid: String)? {
        lock.withLock { terminatedApps.last }
    }

    public func setError(_ error: Error?) {
        lock.withLock { errorToThrow = error }
    }

    public func setOutcome(_ outcome: AppTerminationOutcome) {
        lock.withLock { self.outcome = outcome }
    }

    @discardableResult
    public func terminateApp(bundleIdentifier: String, deviceUdid: String) async throws -> AppTerminationOutcome {
        // The real service suspends here; yielding keeps the mock a genuine suspension point so
        // callers are exercised the same way.
        await Task.yield()

        let (error, outcome): (Error?, AppTerminationOutcome) = lock.withLock {
            terminatedApps.append((bundleIdentifier, deviceUdid))
            didTerminate = true

            return (errorToThrow, self.outcome)
        }

        if let error {
            throw error
        }

        return outcome
    }
}
