//
//  DeviceManagerRecentAppsTests.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 05.09.26.
//

import Combine
import Foundation
import Testing
@testable import SimulatorManager

/// The recent-apps list is the one part of the menu the panel rewrite was forbidden to change:
/// deduped by bundle identifier plus device UDID, sorted by most recent timestamp, and capped.
/// Nothing in the rewrite touches `DeviceManager`, so these cases exist to prove that rather than
/// assert it.
@Suite("DeviceManager recent apps")
@MainActor
struct DeviceManagerRecentAppsTests {
    @Test("Recent apps are ordered most recent first")
    func recentAppsAreSortedByTimestamp() async {
        let recorder = Recorder()
        let device = TestDataHelpers.createMockDevice(udid: "device-1")
        let now = Date()

        recorder.manager.updateRecentApps([
            makeChange(bundleIdentifier: "com.test.old", device: device, timestamp: now.addingTimeInterval(-300)),
            makeChange(bundleIdentifier: "com.test.new", device: device, timestamp: now),
            makeChange(bundleIdentifier: "com.test.middle", device: device, timestamp: now.addingTimeInterval(-60))
        ])
        await drainMainQueue()

        #expect(recorder.bundleIdentifiers == ["com.test.new", "com.test.middle", "com.test.old"])
    }

    @Test("An update replaces the existing entry for the same app on the same device")
    func updatesDoNotDuplicate() async throws {
        let recorder = Recorder()
        let device = TestDataHelpers.createMockDevice(udid: "device-1")
        let now = Date()

        recorder.manager.updateRecentApps([
            makeChange(bundleIdentifier: "com.test.app", device: device, timestamp: now.addingTimeInterval(-300))
        ])
        recorder.manager.updateRecentApps([
            makeChange(bundleIdentifier: "com.test.app", device: device, changeType: .updated, timestamp: now)
        ])
        await drainMainQueue()

        try #require(recorder.latest.count == 1)
        #expect(recorder.latest[0].timestamp == now)
    }

    @Test("The same app on two simulators stays two entries")
    func theSameAppOnTwoDevicesIsNotDeduped() async {
        let recorder = Recorder()
        let first = TestDataHelpers.createMockDevice(udid: "device-1")
        let second = TestDataHelpers.createMockDevice(udid: "device-2")

        recorder.manager.updateRecentApps([
            makeChange(bundleIdentifier: "com.test.app", device: first),
            makeChange(bundleIdentifier: "com.test.app", device: second)
        ])
        await drainMainQueue()

        #expect(recorder.latest.count == 2)
        #expect(Set(recorder.latest.map(\.device.udid)) == ["device-1", "device-2"])
    }

    @Test("Removing an app drops it from the list")
    func removalDropsTheEntry() async {
        let recorder = Recorder()
        let device = TestDataHelpers.createMockDevice(udid: "device-1")

        recorder.manager.updateRecentApps([makeChange(bundleIdentifier: "com.test.app", device: device)])
        recorder.manager.updateRecentApps([
            makeChange(bundleIdentifier: "com.test.app", device: device, changeType: .removed)
        ])
        await drainMainQueue()

        #expect(recorder.latest.isEmpty)
    }

    @Test("The list is capped, keeping the most recent entries")
    func theListIsCapped() async throws {
        let recorder = Recorder()
        let device = TestDataHelpers.createMockDevice(udid: "device-1")
        let now = Date()
        let changes = (0 ..< 30).map { index in
            makeChange(bundleIdentifier: "com.test.app\(index)",
                       device: device,
                       timestamp: now.addingTimeInterval(TimeInterval(index)))
        }

        recorder.manager.updateRecentApps(changes)
        await drainMainQueue()

        try #require(recorder.latest.count == 20)
        // Newest first, and the oldest ten are the ones dropped.
        #expect(recorder.bundleIdentifiers.first == "com.test.app29")
        #expect(recorder.bundleIdentifiers.last == "com.test.app10")
    }
}

// MARK: - Helpers

@MainActor
private final class Recorder {
    let manager = DeviceManager(devicesDirectoryURL: nil)

    private(set) var latest: [AppChange] = []
    private var cancellable: AnyCancellable?

    init() {
        cancellable = manager.recentInstalledApps.sink { [weak self] changes in
            self?.latest = changes
        }
    }

    var bundleIdentifiers: [String] {
        latest.map(\.app.bundleIdentifier)
    }
}

private extension DeviceManagerRecentAppsTests {
    func makeChange(
        bundleIdentifier: String,
        device: Device,
        changeType: ChangeType = .installed,
        timestamp: Date = Date()
    ) -> AppChange {
        AppChange(app: TestDataHelpers.createMockApp(bundleIdentifier: bundleIdentifier),
                  device: device,
                  changeType: changeType,
                  timestamp: timestamp)
    }
}
