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

    @Test("Deduplication runs before the cap, so duplicates don't shorten the list")
    func dedupesBeforeCap() {
        let changes = [
            change("com.example.app", on: iPhone, secondsAgo: 1),
            change("com.example.app", on: iPhone, secondsAgo: 2),
            change("com.example.other", on: iPhone, secondsAgo: 3)
        ]

        #expect(RecentApps.initial(from: changes, limit: 2).map(\.app.bundleIdentifier) == ["com.example.app", "com.example.other"])
    }

    @Test("Hiding test runners drops them before the cap, so they take no slots")
    func hidingTestRunnersHappensBeforeCap() {
        let runners = (0 ..< 5).map { change("com.example.Tests\($0).xctrunner", on: iPhone, secondsAgo: TimeInterval($0), isTestRunner: true) }
        let regular = (0 ..< 4).map { change("com.example.app\($0)", on: iPhone, secondsAgo: TimeInterval(10 + $0)) }

        let hidden = RecentApps.initial(from: runners + regular, limit: 4, hidingTestRunners: true)
        let shown = RecentApps.initial(from: runners + regular, limit: 4)

        #expect(hidden.map(\.app.bundleIdentifier) == regular.map(\.app.bundleIdentifier))
        #expect(shown.allSatisfy { $0.app.isTestRunner })
    }

    @Test("Retained entries keep the newest of each kind, so either visibility can be rebuilt")
    func retainedKeepsBothKinds() {
        let runners = (0 ..< 25).map { change("com.example.Tests\($0).xctrunner", on: iPhone, secondsAgo: TimeInterval($0), isTestRunner: true) }
        let regular = (0 ..< 25).map { change("com.example.app\($0)", on: iPhone, secondsAgo: TimeInterval(100 + $0)) }
        let sorted = (runners + regular).sorted { $0.timestamp > $1.timestamp }

        let retained = RecentApps.retained(from: sorted)

        #expect(retained.count == 2 * RecentApps.maxCount)
        #expect(RecentApps.visible(from: retained, hidingTestRunners: true).map(\.app.bundleIdentifier)
            == regular.prefix(RecentApps.maxCount).map(\.app.bundleIdentifier))
        #expect(RecentApps.visible(from: retained, hidingTestRunners: false).allSatisfy { $0.app.isTestRunner })
    }

    private func change(
        _ bundleIdentifier: String,
        on device: Device,
        secondsAgo: TimeInterval,
        isTestRunner: Bool = false
    ) -> AppChange {
        let app = SimulatoriOSApp(displayName: bundleIdentifier,
                                  bundleIdentifier: bundleIdentifier,
                                  appDocumentsFolderURL: nil,
                                  appPackageURL: nil,
                                  hasWatchApp: false,
                                  userDefaultsDomains: [],
                                  isTestRunner: isTestRunner)
        return AppChange(app: app, device: device, changeType: .installed, timestamp: now.addingTimeInterval(-secondsAgo))
    }
}
