import Foundation
@testable import SimulatorManager

@MainActor
final class MockContainerContentCopier: ContainerContentCopying {
    struct UserDefaultsRequest: Equatable {
        let url: URL
        let preferredPlistName: String
        let subject: String
    }

    private(set) var copiedPaths: [URL] = []
    private(set) var userDefaultsRequests: [UserDefaultsRequest] = []

    var lastCopiedPath: URL? {
        copiedPaths.last
    }

    var lastUserDefaultsRequest: UserDefaultsRequest? {
        userDefaultsRequests.last
    }

    func copyPath(of url: URL) {
        copiedPaths.append(url)
    }

    func copyUserDefaultsJSON(fromPreferencesDirectoryAt url: URL, preferredPlistName: String, subject: String) {
        userDefaultsRequests.append(UserDefaultsRequest(url: url,
                                                        preferredPlistName: preferredPlistName,
                                                        subject: subject))
    }
}
