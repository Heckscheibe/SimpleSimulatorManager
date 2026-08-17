import Foundation
@testable import SimulatorManager

@MainActor
final class MockDestructiveActionConfirmer: DestructiveActionConfirming {
    var shouldConfirm = true

    private(set) var confirmedSimulatorCounts: [Int] = []

    var wasAsked: Bool {
        !confirmedSimulatorCounts.isEmpty
    }

    func confirmPermanentSimulatorDeletion(simulatorCount: Int) -> Bool {
        confirmedSimulatorCounts.append(simulatorCount)
        return shouldConfirm
    }
}
