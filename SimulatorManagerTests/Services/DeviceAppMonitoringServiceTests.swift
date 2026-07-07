//
//  DeviceAppMonitoringServiceTests.swift
//  SimulatorManagerTests
//

import Foundation
import Testing
@testable import SimulatorManager

@Suite("DeviceAppMonitoringService Change Detection")
struct DeviceAppMonitoringServiceTests {
    private let device = TestDataHelpers.createMockDevice()
    private let now = Date()

    private func app(_ bundleIdentifier: String, modifiedAt: Date? = nil) -> MockSimulatorApp {
        MockSimulatorApp(
            bundleIdentifier: bundleIdentifier,
            displayName: bundleIdentifier,
            contentModifiedAt: modifiedAt
        )
    }

    @Test("Newly installed apps are detected")
    func detectsInstalledApps() {
        let installDate = now.addingTimeInterval(-10)
        let changes = DeviceAppMonitoringService.computeAppChanges(
            previousApps: [app("com.test.existing", modifiedAt: now.addingTimeInterval(-100))],
            currentApps: [
                app("com.test.existing", modifiedAt: now.addingTimeInterval(-100)),
                app("com.test.new", modifiedAt: installDate)
            ],
            device: device,
            now: now
        )

        #expect(changes.count == 1)
        #expect(changes.first?.changeType == .installed)
        #expect(changes.first?.app.bundleIdentifier == "com.test.new")
        #expect(changes.first?.timestamp == installDate)
    }

    @Test("Removed apps are detected")
    func detectsRemovedApps() {
        let changes = DeviceAppMonitoringService.computeAppChanges(
            previousApps: [
                app("com.test.keep", modifiedAt: now.addingTimeInterval(-100)),
                app("com.test.gone", modifiedAt: now.addingTimeInterval(-100))
            ],
            currentApps: [app("com.test.keep", modifiedAt: now.addingTimeInterval(-100))],
            device: device,
            now: now
        )

        #expect(changes.count == 1)
        #expect(changes.first?.changeType == .removed)
        #expect(changes.first?.app.bundleIdentifier == "com.test.gone")
    }

    @Test("Apps are only marked as updated when their content changed")
    func detectsRealUpdatesOnly() {
        let oldDate = now.addingTimeInterval(-100)
        let newDate = now.addingTimeInterval(-1)

        let changes = DeviceAppMonitoringService.computeAppChanges(
            previousApps: [
                app("com.test.updated", modifiedAt: oldDate),
                app("com.test.untouched", modifiedAt: oldDate)
            ],
            currentApps: [
                app("com.test.updated", modifiedAt: newDate),
                app("com.test.untouched", modifiedAt: oldDate)
            ],
            device: device,
            now: now
        )

        #expect(changes.count == 1)
        #expect(changes.first?.changeType == .updated)
        #expect(changes.first?.app.bundleIdentifier == "com.test.updated")
        #expect(changes.first?.timestamp == newDate)
    }

    @Test("Apps without modification dates are not flagged as updated")
    func missingDatesAreConservative() {
        let changes = DeviceAppMonitoringService.computeAppChanges(
            previousApps: [app("com.test.app")],
            currentApps: [app("com.test.app")],
            device: device,
            now: now
        )

        #expect(changes.isEmpty)
    }

    @Test("Unchanged snapshots produce no changes")
    func noChangesForIdenticalSnapshots() {
        let apps = [
            app("com.test.one", modifiedAt: now.addingTimeInterval(-50)),
            app("com.test.two", modifiedAt: now.addingTimeInterval(-20))
        ]

        let changes = DeviceAppMonitoringService.computeAppChanges(
            previousApps: apps,
            currentApps: apps,
            device: device,
            now: now
        )

        #expect(changes.isEmpty)
    }

    @Test("Duplicate bundle identifiers do not crash and keep the newest container")
    func duplicateBundleIdentifiersAreTolerated() {
        let older = app("com.test.dup", modifiedAt: now.addingTimeInterval(-100))
        let newer = app("com.test.dup", modifiedAt: now.addingTimeInterval(-1))

        // A stale container plus a fresh one share a bundle identifier; this must not trap.
        let changes = DeviceAppMonitoringService.computeAppChanges(
            previousApps: [],
            currentApps: [older, newer],
            device: device,
            now: now
        )

        #expect(changes.count == 1)
        #expect(changes.first?.changeType == .installed)
        #expect(changes.first?.timestamp == newer.contentModifiedAt)
    }

    @Test("Mixed install, update, and removal in one event")
    func mixedChanges() {
        let oldDate = now.addingTimeInterval(-100)
        let newDate = now.addingTimeInterval(-1)

        let changes = DeviceAppMonitoringService.computeAppChanges(
            previousApps: [
                app("com.test.updated", modifiedAt: oldDate),
                app("com.test.removed", modifiedAt: oldDate)
            ],
            currentApps: [
                app("com.test.updated", modifiedAt: newDate),
                app("com.test.installed", modifiedAt: newDate)
            ],
            device: device,
            now: now
        )

        #expect(changes.count == 3)
        #expect(changes.contains { $0.changeType == .installed && $0.app.bundleIdentifier == "com.test.installed" })
        #expect(changes.contains { $0.changeType == .updated && $0.app.bundleIdentifier == "com.test.updated" })
        #expect(changes.contains { $0.changeType == .removed && $0.app.bundleIdentifier == "com.test.removed" })
    }
}
