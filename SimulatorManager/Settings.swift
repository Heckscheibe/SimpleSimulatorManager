//
//  Settings.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 24.11.23.
//

import Foundation

class Settings: ObservableObject {
    private enum Keys: String, CaseIterable {
        case showTVOS
        case showVisionOS
        case showIPadOS
        case showIOS
        case showWatchOS
        case showRecentApps
    }
    
    @Published var visiblePlatforms = Set<SimulatorPlatform>()
    
    init() {
        for item in Keys.allCases where userDefaults?.value(forKey: item.rawValue) == nil {
            userDefaults?.setValue(true, forKey: item.rawValue)
        }
        updateVisiblePlatforms()
    }
    
    let userDefaults = UserDefaults(suiteName: "SimulatorManager")
    
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
            userDefaults?.setValue(newValue, forKey: Keys.showRecentApps.rawValue)
        }
    }
}

private extension Settings {
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
