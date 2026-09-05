//
//  MenuSearchServiceTests.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 04.09.26.
//

import Foundation
import Testing
@testable import SimulatorManager

@Suite("MenuSearchService Tests")
struct MenuSearchServiceTests {
    // MARK: - Matched fields

    @Test("A query matches an app's display name")
    func matchesAppDisplayName() {
        let device = makeDevice(apps: [makeApp(bundleIdentifier: "com.test.one", displayName: "Weather Station")])
        let service = makeService(devices: [device])

        #expect(titles(service.results(for: "weather")) == ["Weather Station"])
    }

    @Test("A query matches an app's bundle identifier")
    func matchesBundleIdentifier() {
        let device = makeDevice(apps: [makeApp(bundleIdentifier: "com.example.payments", displayName: "Wallet")])
        let service = makeService(devices: [device])

        #expect(titles(service.results(for: "com.example.payments")) == ["Wallet"])
    }

    @Test("A query matches a device's name")
    func matchesDeviceName() {
        let service = makeService(devices: [makeDevice(name: "iPhone 16 Pro", osVersion: "18.2")])

        #expect(titles(service.results(for: "16 pro")) == ["iPhone 16 Pro"])
    }

    @Test("A query matches a device's OS version")
    func matchesOSVersion() {
        let service = makeService(devices: [makeDevice(name: "iPhone 16 Pro", osVersion: "18.2")])

        #expect(titles(service.results(for: "18.2")) == ["iPhone 16 Pro"])
    }

    @Test("A query matches a device's name and OS version joined")
    func matchesCombinedDeviceNameAndOSVersion() {
        let service = makeService(devices: [makeDevice(name: "iPhone 16 Pro", osVersion: "18.2")])

        #expect(titles(service.results(for: "iphone 16 pro 18.2")) == ["iPhone 16 Pro"])
    }

    @Test("Matching ignores case")
    func matchingIsCaseInsensitive() {
        let device = makeDevice(apps: [makeApp(bundleIdentifier: "com.test.safari", displayName: "Safari")])
        let service = makeService(devices: [device])

        #expect(titles(service.results(for: "SAFARI")) == ["Safari"])
        #expect(titles(service.results(for: "sAfArI")) == ["Safari"])
    }

    @Test("Matching ignores diacritics in both the query and the indexed text")
    func matchingIsDiacriticInsensitive() {
        let device = makeDevice(apps: [
            makeApp(bundleIdentifier: "com.test.cafe", displayName: "Café Manager"),
            makeApp(bundleIdentifier: "com.test.metro", displayName: "Metro")
        ])
        let service = makeService(devices: [device])

        #expect(titles(service.results(for: "cafe")) == ["Café Manager"])
        #expect(titles(service.results(for: "métro")) == ["Metro"])
    }

    // MARK: - Ranking

    @Test("Recent apps rank above every non-recent match")
    func recentAppsRankFirst() {
        let recentApp = makeApp(bundleIdentifier: "com.test.zzz", displayName: "Zzz App")
        let otherApp = makeApp(bundleIdentifier: "com.test.aaa", displayName: "Aaa App")
        let device = makeDevice(apps: [otherApp, recentApp])
        let recentChange = AppChange(app: recentApp, device: device, changeType: .installed, timestamp: Date())
        let service = makeService(devices: [device], recentApps: [recentChange])

        // Alphabetically "Aaa App" would win; being recent is what puts "Zzz App" on top.
        #expect(titles(service.results(for: "app")) == ["Zzz App", "Aaa App"])
    }

    @Test("Recent apps are ordered by timestamp, most recent first")
    func recentAppsOrderedByTimestamp() {
        let olderApp = makeApp(bundleIdentifier: "com.test.alpha", displayName: "Alpha App")
        let newerApp = makeApp(bundleIdentifier: "com.test.beta", displayName: "Beta App")
        let device = makeDevice(apps: [olderApp, newerApp])
        let now = Date()
        let service = makeService(devices: [device],
                                  recentApps: [
                                      AppChange(app: olderApp,
                                                device: device,
                                                changeType: .installed,
                                                timestamp: now.addingTimeInterval(-100)),
                                      AppChange(app: newerApp,
                                                device: device,
                                                changeType: .installed,
                                                timestamp: now)
                                  ])

        #expect(titles(service.results(for: "app")) == ["Beta App", "Alpha App"])
    }

    @Test("A prefix match beats a word-boundary match, which beats a plain substring match")
    func matchQualityOrdersResults() {
        let device = makeDevice(name: "Test Device", osVersion: "1.0", apps: [
            makeApp(bundleIdentifier: "com.test.three", displayName: "Prepay"),
            makeApp(bundleIdentifier: "com.test.two", displayName: "Apple Wallet Pay"),
            makeApp(bundleIdentifier: "com.test.one", displayName: "Payments")
        ])
        let service = makeService(devices: [device])

        #expect(titles(service.results(for: "pay")) == ["Payments", "Apple Wallet Pay", "Prepay"])
    }

    @Test("At equal match quality, a hit on a name beats a hit on a bundle identifier")
    func primaryFieldBeatsSecondaryField() {
        let device = makeDevice(name: "Test Device", osVersion: "1.0", apps: [
            makeApp(bundleIdentifier: "wallet.example.app", displayName: "Alpha"),
            makeApp(bundleIdentifier: "com.test.wal", displayName: "Wallet Pro")
        ])
        let service = makeService(devices: [device])

        // Both are prefix matches, and "Alpha" sorts first alphabetically — the field tier is the
        // only thing that can put "Wallet Pro" on top.
        #expect(titles(service.results(for: "wallet")) == ["Wallet Pro", "Alpha"])
    }

    @Test("At equal match quality, a device ranks above an app")
    func devicesRankAboveAppsAtEqualQuality() {
        let device = makeDevice(name: "Sparrow", osVersion: "1.0", apps: [
            makeApp(bundleIdentifier: "com.test.sparrow", displayName: "Sparrow")
        ])
        let service = makeService(devices: [device])
        let results = service.results(for: "sparrow")

        #expect(titles(results) == ["Sparrow", "Sparrow"])
        #expect(results.first?.app == nil)
        #expect(results.last?.app != nil)
    }

    @Test("The same query returns an identically ordered list every time")
    func orderingIsDeterministic() {
        let service = makeService(devices: [
            makeDevice(udid: "device-1", name: "iPhone 16", osVersion: "18.2", apps: [
                makeApp(bundleIdentifier: "com.test.one", displayName: "Test App"),
                makeApp(bundleIdentifier: "com.test.two", displayName: "Test App")
            ]),
            makeDevice(udid: "device-2", name: "iPhone 16", osVersion: "18.1", apps: [
                makeApp(bundleIdentifier: "com.test.one", displayName: "Test App")
            ])
        ])

        let first = service.results(for: "test").map(\.id)
        let second = service.results(for: "test").map(\.id)

        #expect(first == second)
        #expect(!first.isEmpty)
    }

    // MARK: - Index contents

    @Test("An app installed on several devices yields one result per device, each naming its own")
    func appOnSeveralDevicesYieldsOneResultPerDevice() throws {
        let sharedApp = makeApp(bundleIdentifier: "com.test.shared", displayName: "Shared App")
        let service = makeService(devices: [
            makeDevice(udid: "device-1", name: "iPhone 16", osVersion: "18.2", apps: [sharedApp]),
            makeDevice(udid: "device-2", name: "iPad Pro", osVersion: "18.1", platform: .iPad, apps: [sharedApp])
        ])

        let results = service.results(for: "shared app")
        try #require(results.count == 2)

        #expect(Set(results.map(\.id)).count == 2)
        #expect(Set(results.compactMap(\.subtitle)) == ["iPhone 16 18.2", "iPad Pro 18.1"])
    }

    @Test("A device on a hidden platform, and every app on it, is left out of the index")
    func hiddenPlatformsAreExcluded() {
        let appleTV = makeDevice(udid: "appletv-1",
                                 name: "Apple TV 4K",
                                 osVersion: "18.2",
                                 platform: .appleTV,
                                 apps: [makeApp(bundleIdentifier: "com.test.tv", displayName: "TV App")])
        let service = MenuSearchService()
        service.updateIndex(devices: [appleTV], recentApps: [], visiblePlatforms: [.iPhone, .iPad])

        #expect(service.results(for: "apple tv").isEmpty)
        #expect(service.results(for: "tv app").isEmpty)
    }

    @Test("Rebuilding the index replaces its previous contents")
    func updatingTheIndexReplacesIt() {
        let service = makeService(devices: [makeDevice(udid: "device-1", name: "iPhone 16", osVersion: "18.2")])
        #expect(!service.results(for: "iphone").isEmpty)

        service.updateIndex(devices: [], recentApps: [], visiblePlatforms: allPlatforms)

        #expect(service.results(for: "iphone").isEmpty)
    }

    @Test("A recent app whose device is not indexed contributes nothing")
    func recentAppForUnknownDeviceIsIgnored() {
        let goneDevice = makeDevice(udid: "gone", name: "Old iPhone", osVersion: "17.0")
        let goneApp = makeApp(bundleIdentifier: "com.test.gone", displayName: "Gone App")
        let goneChange = AppChange(app: goneApp, device: goneDevice, changeType: .installed, timestamp: Date())
        let device = makeDevice(udid: "device-1", name: "iPhone 16", osVersion: "18.2")
        let service = makeService(devices: [device], recentApps: [goneChange])

        #expect(service.results(for: "gone").isEmpty)
    }

    // MARK: - Empty results

    @Test("An empty query returns nothing")
    func emptyQueryReturnsNothing() {
        let device = makeDevice(apps: [makeApp(bundleIdentifier: "com.test.one", displayName: "Test App")])
        let service = makeService(devices: [device])

        #expect(service.results(for: "").isEmpty)
    }

    @Test("A whitespace-only query returns nothing")
    func whitespaceOnlyQueryReturnsNothing() {
        let device = makeDevice(apps: [makeApp(bundleIdentifier: "com.test.one", displayName: "Test App")])
        let service = makeService(devices: [device])

        #expect(service.results(for: "   ").isEmpty)
        #expect(service.results(for: "\n\t ").isEmpty)
    }

    @Test("A query that matches nothing returns nothing")
    func noMatchQueryReturnsNothing() {
        let device = makeDevice(apps: [makeApp(bundleIdentifier: "com.test.one", displayName: "Test App")])
        let service = makeService(devices: [device])

        #expect(service.results(for: "definitely-not-installed").isEmpty)
    }

    @Test("Searching before the index is built returns nothing")
    func searchingBeforeIndexingReturnsNothing() {
        #expect(MenuSearchService().results(for: "anything").isEmpty)
    }
}

// MARK: - Helpers

private extension MenuSearchServiceTests {
    var allPlatforms: Set<SimulatorPlatform> {
        [.iPhone, .iPad, .watch, .appleTV, .visionPro, .iPodTouch]
    }

    func makeService(devices: [Device], recentApps: [AppChange] = []) -> MenuSearchService {
        let service = MenuSearchService()
        service.updateIndex(devices: devices, recentApps: recentApps, visiblePlatforms: allPlatforms)

        return service
    }

    func makeDevice(
        udid: String = "test-device",
        name: String = "iPhone 16",
        osVersion: String = "18.2",
        platform: SimulatorPlatform = .iPhone,
        apps: [any SimulatorApp] = []
    ) -> Device {
        let device = TestDataHelpers.createMockDevice(udid: udid,
                                                      name: name,
                                                      simulatorPlatform: platform,
                                                      osVersion: osVersion)
        device.apps = apps

        return device
    }

    func makeApp(bundleIdentifier: String, displayName: String) -> MockSimulatorApp {
        TestDataHelpers.createMockApp(bundleIdentifier: bundleIdentifier, displayName: displayName)
    }

    func titles(_ results: [MenuSearchResult]) -> [String] {
        results.map(\.title)
    }
}
