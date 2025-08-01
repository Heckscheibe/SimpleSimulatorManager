//
//  Settings.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 24.11.23.
//

import Foundation

struct Settings {
    private enum Keys: String, CaseIterable {
        case showAppleTV
        case showVisionPro
        case showIPad
        case showIPhone
        case showWatch
        case showRecentApps
    }
    
    init() {
        for item in Keys.allCases where userDefaults?.value(forKey: item.rawValue) == nil {
            userDefaults?.setValue(true, forKey: item.rawValue)
        }
    }
    
    let userDefaults = UserDefaults(suiteName: "SimulatorManager")
    
    var showAppleTV: Bool {
        get {
            userDefaults?.bool(forKey: Keys.showAppleTV.rawValue) ?? true
        }
        set {
            userDefaults?.setValue(newValue, forKey: Keys.showAppleTV.rawValue)
        }
    }

    var showVisionPro: Bool {
        get {
            userDefaults?.bool(forKey: Keys.showVisionPro.rawValue) ?? true
        }
        set {
            userDefaults?.setValue(newValue, forKey: Keys.showVisionPro.rawValue)
        }
    }
    
    var showIPad: Bool {
        get {
            userDefaults?.bool(forKey: Keys.showIPad.rawValue) ?? true
        }
        set {
            userDefaults?.setValue(newValue, forKey: Keys.showIPad.rawValue)
        }
    }
    
    var showIPhone: Bool {
        get {
            userDefaults?.bool(forKey: Keys.showIPhone.rawValue) ?? true
        }
        set {
            userDefaults?.setValue(newValue, forKey: Keys.showIPhone.rawValue)
        }
    }
    
    var showWatch: Bool {
        get {
            userDefaults?.bool(forKey: Keys.showWatch.rawValue) ?? true
        }
        set {
            userDefaults?.setValue(newValue, forKey: Keys.showWatch.rawValue)
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
