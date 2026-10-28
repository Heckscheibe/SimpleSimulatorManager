// The protocol requirement is async; the mock answers at once.
// swiftlint:disable async_without_await

import Foundation
@testable import SimulatorManager

@MainActor
final class MockSnapshotDestinationChooser: SnapshotDestinationChoosing {
    struct Request: Equatable {
        let message: String?
        let startingAt: URL?
        let offersUseAsDefault: Bool
    }

    /// Answered in order; `nil` is the user cancelling. Once used up, every request is cancelled.
    var choices: [SnapshotDestinationChoice?]
    private(set) var requests: [Request] = []
    private(set) var bringAppForwardCount = 0

    init(choices: [SnapshotDestinationChoice?] = []) {
        self.choices = choices
    }

    func bringAppForward() {
        bringAppForwardCount += 1
    }

    func chooseFolder(message: String?, startingAt directoryURL: URL?, offersUseAsDefault: Bool) async -> SnapshotDestinationChoice? {
        requests.append(Request(message: message, startingAt: directoryURL, offersUseAsDefault: offersUseAsDefault))

        return choices.isEmpty ? nil : choices.removeFirst()
    }
}
