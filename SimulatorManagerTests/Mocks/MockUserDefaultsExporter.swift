import Foundation
@testable import SimulatorManager

/// Records what an export was asked for and returns a canned result, so copy behaviour can be
/// tested without laying out a container on disk.
final class MockUserDefaultsExporter: UserDefaultsExporting, @unchecked Sendable {
    struct Request: Equatable {
        let url: URL
        let ownDomain: String
    }

    enum MockError: Error, LocalizedError {
        case exportFailed

        var errorDescription: String? {
            "Mock export failure"
        }
    }

    var result: Result<String, Error> = .success("{}")

    private(set) var requests: [Request] = []

    var lastRequest: Request? {
        requests.last
    }

    func exportJSON(fromPreferencesDirectoryAt url: URL, ownDomain: String) throws -> String {
        requests.append(Request(url: url, ownDomain: ownDomain))

        return try result.get()
    }
}
