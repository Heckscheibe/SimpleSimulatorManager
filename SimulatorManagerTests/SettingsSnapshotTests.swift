//
//  SettingsSnapshotTests.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 20.10.26.
//

import Foundation
import Testing
@testable import SimulatorManager

@Suite("Settings Snapshot Tests")
struct SettingsSnapshotTests {
    @Test("A fresh installation saves snapshots to Downloads")
    func defaultsToDownloads() throws {
        let suiteName = Self.makeSuiteName()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let settings = Settings(userDefaults: UserDefaults(suiteName: suiteName))
        let downloads = try #require(FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first)

        #expect(settings.snapshotExportFolder?.standardizedFileURL == downloads.standardizedFileURL)
    }

    @Test("Ask Every Time is remembered, and is not mistaken for never configured")
    func askEveryTimePersists() {
        let suiteName = Self.makeSuiteName()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        Settings(userDefaults: UserDefaults(suiteName: suiteName)).snapshotExportFolder = nil

        #expect(Settings(userDefaults: UserDefaults(suiteName: suiteName)).snapshotExportFolder == nil)
    }

    @Test("A chosen folder survives a relaunch")
    func chosenFolderPersists() {
        let suiteName = Self.makeSuiteName()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let folder = URL(fileURLWithPath: "/tmp/Snapshots Here", isDirectory: true)
        Settings(userDefaults: UserDefaults(suiteName: suiteName)).snapshotExportFolder = folder

        #expect(Settings(userDefaults: UserDefaults(suiteName: suiteName)).snapshotExportFolder?.path == folder.path)
    }

    @Test("Changing the folder tells observers, so the settings window follows")
    func notifiesObservers() {
        let suiteName = Self.makeSuiteName()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let settings = Settings(userDefaults: UserDefaults(suiteName: suiteName))
        var notifications = 0
        let cancellable = settings.objectWillChange.sink { notifications += 1 }

        settings.snapshotExportFolder = nil
        settings.includeCachesInSnapshots = true

        #expect(notifications == 2)
        cancellable.cancel()
    }

    static func makeSuiteName() -> String {
        "SettingsSnapshotTests.\(UUID().uuidString)"
    }
}
