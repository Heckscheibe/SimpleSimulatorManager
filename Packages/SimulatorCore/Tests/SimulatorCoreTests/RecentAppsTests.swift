import Foundation
import Testing
@testable import SimulatorCore

@Suite("RecentApps")
struct RecentAppsTests {
    private let iPhone = Device(udid: "iphone-udid", name: "iPhone 16 Pro", state: .running, simulatorPlatform: .iPhone, osVersion: "iOS 26.1")
    private let iPad = Device(udid: "ipad-udid", name: "iPad Air", state: .off, simulatorPlatform: .iPad, osVersion: "iOS 26.1")
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Empty input gives an empty list")
    func emptyInput() {
        #expect(RecentApps.initial(from: []).isEmpty)
    }

    @Test("Most recent change comes first")
    func sortsMostRecentFirst() {
        let changes = [
            change("com.example.old", on: iPhone, secondsAgo: 300),
            change("com.example.new", on: iPhone, secondsAgo: 10),
            change("com.example.middle", on: iPhone, secondsAgo: 100)
        ]

        #expect(RecentApps.initial(from: changes).map(\.app.bundleIdentifier)
            == ["com.example.new", "com.example.middle", "com.example.old"])
    }

    @Test("List is capped at the maximum count")
    func capsAtMaxCount() {
        let changes = (0 ..< (RecentApps.maxCount + 5)).map { index in
            change("com.example.app\(index)", on: iPhone, secondsAgo: TimeInterval(index))
        }

        let recentApps = RecentApps.initial(from: changes)

        #expect(recentApps.count == RecentApps.maxCount)
        #expect(recentApps.first?.app.bundleIdentifier == "com.example.app0")
    }

    @Test("Duplicates by bundle identifier and device keep the most recent entry")
    func dedupesByBundleIdentifierAndDevice() {
        let changes = [
            change("com.example.app", on: iPhone, secondsAgo: 500),
            change("com.example.app", on: iPhone, secondsAgo: 5),
            change("com.example.app", on: iPad, secondsAgo: 50)
        ]

        let recentApps = RecentApps.initial(from: changes)

        #expect(recentApps.count == 2)
        #expect(recentApps.map(\.device.udid) == [iPhone.udid, iPad.udid])
        #expect(recentApps.first?.timestamp == now.addingTimeInterval(-5))
    }

    @Test("Deduplication runs after the cap, as the menu always has")
    func dedupesAfterCap() {
        let changes = [
            change("com.example.app", on: iPhone, secondsAgo: 1),
            change("com.example.app", on: iPhone, secondsAgo: 2),
            change("com.example.other", on: iPhone, secondsAgo: 3)
        ]

        #expect(RecentApps.initial(from: changes, limit: 2).map(\.app.bundleIdentifier) == ["com.example.app"])
    }

    private func change(_ bundleIdentifier: String, on device: Device, secondsAgo: TimeInterval) -> AppChange {
        let app = SimulatoriOSApp(displayName: bundleIdentifier,
                                  bundleIdentifier: bundleIdentifier,
                                  appDocumentsFolderURL: nil,
                                  appPackageURL: nil,
                                  hasWatchApp: false,
                                  userDefaultsDomains: [])
        return AppChange(app: app, device: device, changeType: .installed, timestamp: now.addingTimeInterval(-secondsAgo))
    }
}
