//
//  SnapshotSaveViewModelTests.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 20.10.26.
//

import Foundation
import Testing
@testable import SimulatorCore
@testable import SimulatorManager

@Suite("Snapshot Save View Model Tests")
@MainActor
struct SnapshotSaveViewModelTests {
    static let configuredFolder = URL(fileURLWithPath: "/tmp/configured", isDirectory: true)
    static let chosenFolder = URL(fileURLWithPath: "/tmp/chosen", isDirectory: true)

    @Test("With a default folder, saves there without asking and reveals the result")
    func savesToDefaultFolder() async {
        let environment = Environment()
        defer { environment.tearDown() }

        environment.settings.snapshotExportFolder = Self.configuredFolder
        environment.settings.includeCachesInSnapshots = true

        environment.viewModel.saveSnapshot(of: environment.app, on: environment.device)
        await environment.viewModel.waitForPendingSaves()

        #expect(environment.chooser.requests.isEmpty)
        #expect(environment.chooser.bringAppForwardCount == 0)
        #expect(environment.saver.calls == [.init(directoryURL: Self.configuredFolder, includeCaches: true)])
        #expect(environment.revealed == [Self.configuredFolder.appendingPathComponent("saved", isDirectory: true)])
        #expect(!environment.errorReporter.didReport)
    }

    @Test("Without a default folder, brings the app forward at once and asks where to save")
    func asksWithoutDefaultFolder() async {
        let environment = Environment(choices: [.init(url: Self.chosenFolder, useAsDefault: false)])
        defer { environment.tearDown() }

        environment.settings.snapshotExportFolder = nil

        environment.viewModel.saveSnapshot(of: environment.app, on: environment.device)

        // Synchronously, while the panel the row was picked from is still up.
        #expect(environment.chooser.bringAppForwardCount == 1)

        await environment.viewModel.waitForPendingSaves()

        #expect(environment.chooser.requests.count == 1)
        #expect(environment.chooser.requests.first?.offersUseAsDefault == true)
        #expect(environment.chooser.requests.first?.message == nil)
        #expect(environment.saver.calls.map(\.directoryURL) == [Self.chosenFolder])
        #expect(environment.settings.snapshotExportFolder == nil)
    }

    @Test("Use this folder by default makes the choice the new default")
    func remembersDefault() async {
        let environment = Environment(choices: [.init(url: Self.chosenFolder, useAsDefault: true)])
        defer { environment.tearDown() }

        environment.settings.snapshotExportFolder = nil

        environment.viewModel.saveSnapshot(of: environment.app, on: environment.device)
        await environment.viewModel.waitForPendingSaves()

        #expect(environment.settings.snapshotExportFolder?.path == Self.chosenFolder.path)
    }

    @Test("Cancelling the picker saves nothing and reports nothing")
    func cancelling() async {
        let environment = Environment(choices: [nil])
        defer { environment.tearDown() }

        environment.settings.snapshotExportFolder = nil

        environment.viewModel.saveSnapshot(of: environment.app, on: environment.device)
        await environment.viewModel.waitForPendingSaves()

        #expect(environment.saver.calls.isEmpty)
        #expect(environment.revealed.isEmpty)
        #expect(!environment.errorReporter.didReport)
        #expect(environment.viewModel.progress(for: environment.app, on: environment.device) == nil)
    }

    @Test("An unusable folder asks for another, saying why, rather than saving elsewhere")
    func unusableFolderAsksAgain() async {
        let error = AppSnapshotSaveError.destinationMissing(path: Self.configuredFolder.path)
        let environment = Environment(results: [.failure(error)],
                                      choices: [.init(url: Self.chosenFolder, useAsDefault: false)])
        defer { environment.tearDown() }

        environment.settings.snapshotExportFolder = Self.configuredFolder

        environment.viewModel.saveSnapshot(of: environment.app, on: environment.device)
        await environment.viewModel.waitForPendingSaves()

        #expect(environment.saver.calls.map(\.directoryURL) == [Self.configuredFolder, Self.chosenFolder])
        #expect(environment.chooser.requests.first?.message?.contains(error.localizedDescription) == true)
        #expect(environment.chooser.bringAppForwardCount == 1)
        #expect(environment.revealed.count == 1)
        #expect(!environment.errorReporter.didReport)
    }

    @Test("A failed capture is reported, and nothing is revealed")
    func failureIsReported() async {
        let environment = Environment(results: [.failure(AppSnapshotError.nothingToCapture)])
        defer { environment.tearDown() }

        environment.settings.snapshotExportFolder = Self.configuredFolder

        environment.viewModel.saveSnapshot(of: environment.app, on: environment.device)
        await environment.viewModel.waitForPendingSaves()

        #expect(environment.errorReporter.reports.map(\.title) == ["Could not save a snapshot of Acme"])
        #expect(environment.revealed.isEmpty)
        #expect(environment.viewModel.progress(for: environment.app, on: environment.device) == nil)
    }

    @Test("The contents picked are what is saved")
    func passesContentsThrough() async {
        let environment = Environment()
        defer { environment.tearDown() }

        environment.settings.snapshotExportFolder = Self.configuredFolder

        environment.viewModel.saveSnapshot(of: environment.app, on: environment.device, contents: .userDefaults)
        await environment.viewModel.waitForPendingSaves()

        let expected = MockAppSnapshotSaver.Call(directoryURL: Self.configuredFolder,
                                                 includeCaches: false,
                                                 contents: .userDefaults)
        #expect(environment.saver.calls == [expected])
    }

    @Test("An option that finds nothing is reported as such")
    func nothingInContentsIsReported() async {
        let environment = Environment(results: [.failure(AppSnapshotError.nothingInContents(.databases))])
        defer { environment.tearDown() }

        environment.settings.snapshotExportFolder = Self.configuredFolder

        environment.viewModel.saveSnapshot(of: environment.app, on: environment.device, contents: .databases)
        await environment.viewModel.waitForPendingSaves()

        #expect(environment.errorReporter.reports.map(\.message) == ["This app has no database files to snapshot."])
        #expect(environment.revealed.isEmpty)
    }

    @Test("An app without a data container is refused before anything starts")
    func appWithoutContainer() async {
        let environment = Environment()
        defer { environment.tearDown() }

        let app = TestDataHelpers.createMockApp(displayName: "Empty")

        #expect(!environment.viewModel.canSaveSnapshot(of: app))

        environment.viewModel.saveSnapshot(of: app, on: environment.device)
        await environment.viewModel.waitForPendingSaves()

        #expect(environment.saver.calls.isEmpty)
        #expect(environment.errorReporter.reports.map(\.title) == ["Could not save a snapshot of Empty"])
    }

    @Test("A save in progress is visible, and picking the row again does not start a second")
    func inProgress() async {
        let environment = Environment()
        defer { environment.tearDown() }

        environment.settings.snapshotExportFolder = Self.configuredFolder

        environment.viewModel.saveSnapshot(of: environment.app, on: environment.device)

        #expect(environment.viewModel.progress(for: environment.app, on: environment.device) == 0)

        environment.viewModel.saveSnapshot(of: environment.app, on: environment.device)
        await environment.viewModel.waitForPendingSaves()

        #expect(environment.saver.calls.count == 1)
        #expect(environment.viewModel.progress(for: environment.app, on: environment.device) == nil)
    }

    @Test("The same app on another simulator is a separate save")
    func keyedByDevice() {
        let environment = Environment()
        defer { environment.tearDown() }

        environment.settings.snapshotExportFolder = Self.configuredFolder
        let otherDevice = TestDataHelpers.createMockDevice(udid: "device-2", name: "iPhone 16")

        environment.viewModel.saveSnapshot(of: environment.app, on: environment.device)

        #expect(environment.viewModel.progress(for: environment.app, on: otherDevice) == nil)
    }
}

// MARK: - Environment

@MainActor
private final class Environment {
    let suiteName = "SnapshotSaveViewModelTests.\(UUID().uuidString)"
    let settings: Settings
    let saver: MockAppSnapshotSaver
    let chooser: MockSnapshotDestinationChooser
    let errorReporter = MockUserFacingErrorReporter()
    let viewModel: SnapshotSaveViewModel
    let device = TestDataHelpers.createMockDevice(udid: "device-1", name: "iPhone 17 Pro", osVersion: "iOS 26.1")
    let app = TestDataHelpers.createMockApp(bundleIdentifier: "com.acme.app",
                                            displayName: "Acme",
                                            appDocumentsFolderURL: URL(fileURLWithPath: "/tmp/container", isDirectory: true))
    private let revealRecorder = RevealRecorder()

    var revealed: [URL] {
        revealRecorder.urls
    }

    init(results: [Result<URL, any Error>] = [], choices: [SnapshotDestinationChoice?] = []) {
        let settings = Settings(userDefaults: UserDefaults(suiteName: suiteName))
        let saver = MockAppSnapshotSaver(results: results)
        let chooser = MockSnapshotDestinationChooser(choices: choices)
        let revealRecorder = revealRecorder

        self.settings = settings
        self.saver = saver
        self.chooser = chooser
        viewModel = SnapshotSaveViewModel(saver: saver,
                                          settings: settings,
                                          destinationChooser: chooser,
                                          errorReporter: errorReporter,
                                          revealInFinder: { revealRecorder.urls.append($0) })
    }

    func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
private final class RevealRecorder {
    var urls: [URL] = []
}
