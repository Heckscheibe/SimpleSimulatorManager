//
//  Settings.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 24.11.23.
//

import Foundation

struct Settings {
    private enum Keys: String {
        case showAppleTV
        case showVisionOS
        case showIPadOS
        case showIOS
        case showWatchOS
    }
    
    let userDefaults = UserDefaults(suiteName: "SimulatorManager")
    
    var showAppleTV: Bool {
        get {
            userDefaults?.bool(forKey: Keys.showAppleTV.rawValue) ?? false
        }
        set {
            userDefaults?.setValue(newValue, forKey: Keys.showAppleTV.rawValue)
        }
    }

    var showVisionOS: Bool {
        get {
            userDefaults?.bool(forKey: Keys.showVisionOS.rawValue) ?? false
        }
        set {
            userDefaults?.setValue(newValue, forKey: Keys.showVisionOS.rawValue)
        }
    }
    
    var showIPadOS: Bool {
        get {
            userDefaults?.bool(forKey: Keys.showIPadOS.rawValue) ?? false
        }
        set {
            userDefaults?.setValue(newValue, forKey: Keys.showIPadOS.rawValue)
        }
    }
    
    var showIOS: Bool {
        get {
            userDefaults?.bool(forKey: Keys.showIOS.rawValue) ?? false
        }
        set {
            userDefaults?.setValue(newValue, forKey: Keys.showIOS.rawValue)
        }
    }
    
    var showWatchOS: Bool {
        get {
            userDefaults?.bool(forKey: Keys.showWatchOS.rawValue) ?? false
        }
        set {
            userDefaults?.setValue(newValue, forKey: Keys.showWatchOS.rawValue)
        }
    }
}
