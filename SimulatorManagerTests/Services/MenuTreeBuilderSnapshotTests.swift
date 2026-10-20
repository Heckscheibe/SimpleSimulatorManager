//
//  MenuTreeBuilderSnapshotTests.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 20.10.26.
//

import Foundation
import Testing
@testable import SimulatorCore
@testable import SimulatorManager

@Suite("MenuTreeBuilder Snapshot Tests")
@MainActor
struct MenuTreeBuilderSnapshotTests {
    static let prefix = "device.device-1.app.com.test.acme-acme-container"

    @Test("An app ends its submenu with Save Snapshot to Folder…, fenced by a divider")
    func appOffersSave() async throws {
        let fixture = MenuTreeFixture()
        defer { fixture.tearDown() }

        _ = await Self.installApp(in: fixture)
        let snapshots = Self.makeViewModel(fixture: fixture)

        let nodes = fixture.makeBuilder(snapshotSaveViewModel: snapshots).makeNodes()
        let app = try #require(nodes.node(withID: Self.prefix))
        let save = try #require(app.children.last)

        #expect(save.id == "\(Self.prefix).saveSnapshot")
        #expect(save.title == "Save Snapshot to Folder…")
        #expect(save.isSelectable)
        #expect(!save.isDestructive)
        #expect(save.accessibilityLabel == "Save Snapshot to Folder…")
        #expect(app.children.dropLast().last?.kind.isDivider == true)
        // Not on a modifier: ⌘↩ and ⌥↩ mean "open a different folder".
        #expect(!app.secondaryActions.map(\.title).contains("Save Snapshot to Folder…"))
    }

    @Test("A recent app offers it too")
    func recentAppOffersSave() async throws {
        let fixture = MenuTreeFixture()
        defer { fixture.tearDown() }

        let device = TestDataHelpers.createMockDevice(udid: "device-1", name: "iPhone 16")
        let change = TestDataHelpers.createMockAppChange(app: Self.makeApp(), device: device)
        await fixture.setRecentApps([change])

        let nodes = fixture.makeBuilder(snapshotSaveViewModel: Self.makeViewModel(fixture: fixture)).makeNodes()
        let recentApp = try #require(nodes.node(withID: "recentApp.\(change.id)"))

        #expect(recentApp.children.last?.id == "recentApp.\(change.id).saveSnapshot")
    }

    @Test("An app with no data container is not offered a snapshot")
    func noContainerNoRow() async throws {
        let fixture = MenuTreeFixture()
        defer { fixture.tearDown() }

        let device = TestDataHelpers.createMockDevice(udid: "device-1", name: "iPhone 16")
        let app = TestDataHelpers.createMockApp(bundleIdentifier: "com.test.bare",
                                                displayName: "Bare",
                                                appPackageURL: URL(fileURLWithPath: "/tmp/bare-container/Bare.app"))
        device.apps = [app]
        await fixture.setDevices([device])

        let nodes = fixture.makeBuilder(snapshotSaveViewModel: Self.makeViewModel(fixture: fixture)).makeNodes()
        let appNode = try #require(nodes.node(withID: "device.device-1.app.com.test.bare-bare-container"))

        #expect(!appNode.children.contains { $0.id.hasSuffix(".saveSnapshot") })
        #expect(appNode.children.last?.kind.isDivider != true)
    }

    @Test("A save in progress replaces the row with its progress")
    func showsProgress() async throws {
        let fixture = MenuTreeFixture()
        defer { fixture.tearDown() }

        let (device, app) = await Self.installApp(in: fixture)
        let snapshots = Self.makeViewModel(fixture: fixture)
        fixture.settings.snapshotExportFolder = URL(fileURLWithPath: "/tmp/configured", isDirectory: true)

        snapshots.saveSnapshot(of: app, on: device)

        let nodes = fixture.makeBuilder(snapshotSaveViewModel: snapshots).makeNodes()
        let appNode = try #require(nodes.node(withID: Self.prefix))
        let progress = try #require(appNode.children.last)

        #expect(progress.id == "\(Self.prefix).saveSnapshot.progress")
        #expect(progress.title == "Saving Snapshot… 0%")
        #expect(!progress.isSelectable)

        await snapshots.waitForPendingSaves()
    }

    @Test("Without a snapshot view model the app submenu is unchanged")
    func absentWithoutViewModel() async throws {
        let fixture = MenuTreeFixture()
        defer { fixture.tearDown() }

        _ = await Self.installApp(in: fixture)

        let nodes = fixture.makeBuilder().makeNodes()
        let appNode = try #require(nodes.node(withID: Self.prefix))

        #expect(!appNode.children.contains { $0.id.hasSuffix(".saveSnapshot") })
    }

    @Test("Progress titles round down, so a save never claims 100% before it is done")
    func progressTitle() {
        #expect(MenuTreeBuilder.progressTitle(0.999) == "Saving Snapshot… 99%")
        #expect(MenuTreeBuilder.progressTitle(0.42) == "Saving Snapshot… 42%")
    }
}

private extension MenuTreeBuilderSnapshotTests {
    static func makeApp() -> MockSimulatorApp {
        let root = URL(fileURLWithPath: "/tmp/acme-container")

        return TestDataHelpers.createMockApp(bundleIdentifier: "com.test.acme",
                                             displayName: "Acme",
                                             appDocumentsFolderURL: root.appendingPathComponent("Data"),
                                             appPackageURL: root.appendingPathComponent("Acme.app"))
    }

    static func installApp(in fixture: MenuTreeFixture) async -> (Device, MockSimulatorApp) {
        let device = TestDataHelpers.createMockDevice(udid: "device-1", name: "iPhone 16")
        let app = makeApp()
        device.apps = [app]
        await fixture.setDevices([device])

        return (device, app)
    }

    static func makeViewModel(fixture: MenuTreeFixture) -> SnapshotSaveViewModel {
        SnapshotSaveViewModel(saver: MockAppSnapshotSaver(),
                              settings: fixture.settings,
                              destinationChooser: MockSnapshotDestinationChooser(),
                              errorReporter: MockUserFacingErrorReporter(),
                              revealInFinder: { _ in })
    }
}
