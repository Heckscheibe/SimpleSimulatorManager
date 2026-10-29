import Foundation
@testable import SimulatorManager

@MainActor
final class MockDestructiveActionConfirmer: DestructiveActionConfirming {
    var shouldConfirm = true

    private(set) var confirmedSimulatorCounts: [Int] = []
    private(set) var confirmedRuntimeRequests: [(runtimeCount: Int, totalBytes: Int64, simulatorCount: Int)] = []

    var wasAsked: Bool {
        !confirmedSimulatorCounts.isEmpty || !confirmedRuntimeRequests.isEmpty
    }

    func confirmPermanentSimulatorDeletion(simulatorCount: Int) -> Bool {
        confirmedSimulatorCounts.append(simulatorCount)
        return shouldConfirm
    }

    func confirmRuntimeDeletion(runtimeCount: Int, totalBytes: Int64, simulatorCount: Int) -> Bool {
        confirmedRuntimeRequests.append((runtimeCount, totalBytes, simulatorCount))
        return shouldConfirm
    }
}
