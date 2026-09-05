//
//  Settings.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 24.11.23.
//

import Foundation
import SwiftUI
import os

class Settings: ObservableObject {
    private enum Keys: String, CaseIterable {
        case showTVOS
        case showVisionOS
        case showIPadOS
        case showIOS
        case showWatchOS
        case showRecentApps
    }

    /// Stored separately from ``Keys`` because that enum is initialised to `true` for every case,
    /// which only makes sense for the boolean visibility preferences.
    private enum ShortcutKeys {
        static let globalShortcut = "globalShortcut"
    }

    /// Also outside ``Keys``, for the same reason and the opposite default: caches are left out of
    /// a snapshot unless the user asks for them.
    private enum SnapshotKeys {
        static let includeCaches = "includeCachesInSnapshots"
    }

    @Published var visiblePlatforms = Set<SimulatorPlatform>()

    /// The shortcut that opens the menu bar menu, or `nil` when the user cleared it.
    @Published private(set) var globalShortcut: GlobalShortcut?

    /// - Parameter userDefaults: Injectable so tests can run against a throwaway suite instead of
    ///   the user's real preferences.
    init(userDefaults: UserDefaults? = UserDefaults(suiteName: Settings.defaultSuiteName)) {
        self.userDefaults = userDefaults

        for item in Keys.allCases where userDefaults?.value(forKey: item.rawValue) == nil {
            userDefaults?.setValue(true, forKey: item.rawValue)
        }
        updateVisiblePlatforms()
        globalShortcut = Self.loadGlobalShortcut(from: userDefaults)
    }

    static let defaultSuiteName = "SimulatorManager"

    let userDefaults: UserDefaults?

    /// Updates and persists the global shortcut. Passing `nil` clears it, which is a supported
    /// state: the app then simply has no global shortcut.
    func updateGlobalShortcut(_ shortcut: GlobalShortcut?) {
        globalShortcut = shortcut

        guard let shortcut else {
            // An empty value marks "deliberately cleared" and is distinct from a missing key,
            // which means "never configured" and yields the default shortcut.
            userDefaults?.setValue(Data(), forKey: ShortcutKeys.globalShortcut)

            return
        }
        guard let data = try? JSONEncoder().encode(shortcut) else {
            os_log("Global shortcut could not be encoded and was not persisted")

            return
        }

        userDefaults?.setValue(data, forKey: ShortcutKeys.globalShortcut)
    }
    
    /// Whether a new app container snapshot captures `Library/Caches` and `tmp`.
    ///
    /// Off by default: both are regenerable and are frequently the bulk of a container's size, so
    /// including them would make every snapshot cost far more disk than the state worth keeping.
    var includeCachesInSnapshots: Bool {
        get {
            userDefaults?.bool(forKey: SnapshotKeys.includeCaches) ?? false
        }
        set {
            userDefaults?.setValue(newValue, forKey: SnapshotKeys.includeCaches)
        }
    }

    var showTVOS: Bool {
        get {
            userDefaults?.bool(forKey: Keys.showTVOS.rawValue) ?? true
        }
        set {
            userDefaults?.setValue(newValue, forKey: Keys.showTVOS.rawValue)
            updateVisiblePlatforms()
        }
    }

    var showVisionOS: Bool {
        get {
            userDefaults?.bool(forKey: Keys.showVisionOS.rawValue) ?? true
        }
        set {
            userDefaults?.setValue(newValue, forKey: Keys.showVisionOS.rawValue)
            updateVisiblePlatforms()
        }
    }
    
    var showIPadOS: Bool {
        get {
            userDefaults?.bool(forKey: Keys.showIPadOS.rawValue) ?? true
        }
        set {
            userDefaults?.setValue(newValue, forKey: Keys.showIPadOS.rawValue)
            updateVisiblePlatforms()
        }
    }
    
    var showIOS: Bool {
        get {
            userDefaults?.bool(forKey: Keys.showIOS.rawValue) ?? true
        }
        set {
            userDefaults?.setValue(newValue, forKey: Keys.showIOS.rawValue)
            updateVisiblePlatforms()
        }
    }
    
    var showWatchOS: Bool {
        get {
            userDefaults?.bool(forKey: Keys.showWatchOS.rawValue) ?? true
        }
        set {
            userDefaults?.setValue(newValue, forKey: Keys.showWatchOS.rawValue)
            updateVisiblePlatforms()
        }
    }
    
    var showRecentApps: Bool {
        get {
            userDefaults?.bool(forKey: Keys.showRecentApps.rawValue) ?? true
        }
        set {
            // Unlike the platform preferences this one does not feed `visiblePlatforms`, so
            // observers have to be notified explicitly for the settings window to stay in sync
            // with the menu.
            objectWillChange.send()
            userDefaults?.setValue(newValue, forKey: Keys.showRecentApps.rawValue)
        }
    }

    /// Two-way binding for the boolean preferences, so the settings window and the menu can drive
    /// the same value without duplicating the toggle logic.
    func binding(for keyPath: ReferenceWritableKeyPath<Settings, Bool>) -> Binding<Bool> {
        Binding(get: { self[keyPath: keyPath] },
                set: { self[keyPath: keyPath] = $0 })
    }
}

private extension Settings {
    static func loadGlobalShortcut(from userDefaults: UserDefaults?) -> GlobalShortcut? {
        guard let data = userDefaults?.data(forKey: ShortcutKeys.globalShortcut) else {
            // Never configured: start from the default shortcut.
            return .default
        }
        guard !data.isEmpty else {
            // Deliberately cleared by the user.
            return nil
        }
        guard let shortcut = try? JSONDecoder().decode(GlobalShortcut.self, from: data) else {
            os_log("Stored global shortcut could not be decoded, falling back to the default")

            return .default
        }

        return shortcut
    }

    func updateVisiblePlatforms() {
        visiblePlatforms = Set([
            showTVOS ? SimulatorPlatform.appleTV : nil,
            showVisionOS ? .visionPro : nil,
            showIPadOS ? .iPad : nil,
            showIOS ? .iPhone : nil,
            showIOS ? .iPodTouch : nil,
            showWatchOS ? .watch : nil
        ].compactMap { $0 })
    }
}
