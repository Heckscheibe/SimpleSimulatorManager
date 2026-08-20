//
//  SettingsGlobalShortcutTests.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 11.08.26.
//

import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import SimulatorManager

@Suite("Settings Global Shortcut Tests")
struct SettingsGlobalShortcutTests {
    // MARK: - Defaults

    @Test("A fresh installation starts with the default shortcut")
    func freshInstallationUsesDefaultShortcut() {
        let suite = TestSuite()
        defer { suite.tearDown() }

        let settings = Settings(userDefaults: suite.userDefaults)

        #expect(settings.globalShortcut == .default)
    }

    // MARK: - Persistence

    @Test("A custom shortcut survives a relaunch")
    func customShortcutIsPersisted() {
        let suite = TestSuite()
        defer { suite.tearDown() }

        let shortcut = GlobalShortcut(keyCode: UInt16(kVK_ANSI_K), modifierFlags: [.command, .shift])
        Settings(userDefaults: suite.userDefaults).updateGlobalShortcut(shortcut)

        let relaunched = Settings(userDefaults: suite.userDefaults)

        #expect(relaunched.globalShortcut == shortcut)
    }

    @Test("A cleared shortcut stays cleared across a relaunch")
    func clearedShortcutIsPersisted() {
        let suite = TestSuite()
        defer { suite.tearDown() }

        Settings(userDefaults: suite.userDefaults).updateGlobalShortcut(nil)

        let relaunched = Settings(userDefaults: suite.userDefaults)

        // Distinct from "never configured", which would yield the default shortcut.
        #expect(relaunched.globalShortcut == nil)
    }

    @Test("Clearing and setting again restores a working shortcut")
    func shortcutCanBeSetAfterClearing() {
        let suite = TestSuite()
        defer { suite.tearDown() }

        let settings = Settings(userDefaults: suite.userDefaults)
        settings.updateGlobalShortcut(nil)
        settings.updateGlobalShortcut(.default)

        #expect(Settings(userDefaults: suite.userDefaults).globalShortcut == .default)
    }

    // MARK: - Corrupt Data

    @Test("Undecodable stored data falls back to the default shortcut")
    func corruptDataFallsBackToDefault() {
        let suite = TestSuite()
        defer { suite.tearDown() }

        suite.userDefaults?.setValue(Data("not a shortcut".utf8), forKey: "globalShortcut")

        #expect(Settings(userDefaults: suite.userDefaults).globalShortcut == .default)
    }

    // MARK: - Boolean Preference Bindings

    @Test("The binding helper reads and writes the underlying preference")
    func bindingReadsAndWrites() {
        let suite = TestSuite()
        defer { suite.tearDown() }

        let settings = Settings(userDefaults: suite.userDefaults)
        let binding = settings.binding(for: \.showRecentApps)

        #expect(binding.wrappedValue)

        binding.wrappedValue = false

        #expect(!settings.showRecentApps)
        #expect(!Settings(userDefaults: suite.userDefaults).showRecentApps)
    }
}

/// Throwaway `UserDefaults` suite so tests never touch the user's real preferences.
private struct TestSuite {
    let name = "SimulatorManagerTests.\(UUID().uuidString)"

    var userDefaults: UserDefaults? {
        UserDefaults(suiteName: name)
    }

    func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: name)
    }
}
