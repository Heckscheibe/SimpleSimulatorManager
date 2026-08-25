import Foundation
@testable import SimulatorManager

@MainActor
final class MockUserFacingErrorReporter: UserFacingErrorReporting {
    private(set) var reports: [(title: String, message: String)] = []

    var didReport: Bool {
        !reports.isEmpty
    }

    func report(title: String, message: String) {
        reports.append((title: title, message: message))
    }
}
