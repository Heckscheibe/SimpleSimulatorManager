import Combine
import Foundation
import Testing
@testable import SimulatorCore

@Suite("SimulatorResetService Tests")
struct SimulatorResetServiceTests {
    /// Counts `didResetAllSimulators` emissions without tying the test to the publisher's thread.
    private final class EmissionCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var cancellable: AnyCancellable?

        var emissions: Int {
            lock.withLock { value }
        }

        func increment() {
            lock.withLock { value += 1 }
        }
    }

    @Test("didResetAllSimulators fires once the erase succeeds")
    func resetAllPublishes() async throws {
        // `true` ignores the `simctl erase all` arguments and exits 0, so the real launch path runs
        // without erasing anything.
        let service = SimulatorResetService(simctlLauncherPath: "/usr/bin/true")
        let counter = EmissionCounter()
        counter.cancellable = service.didResetAllSimulators.sink { counter.increment() }

        try await service.resetAllSimulators()

        #expect(counter.emissions == 1)
    }

    @Test("A failed erase throws and does not publish")
    func failedResetDoesNotPublish() async {
        let service = SimulatorResetService(simctlLauncherPath: "/usr/bin/false")
        let counter = EmissionCounter()
        counter.cancellable = service.didResetAllSimulators.sink { counter.increment() }

        await #expect(throws: (any Error).self) {
            try await service.resetAllSimulators()
        }
        #expect(counter.emissions == 0)
    }
}
