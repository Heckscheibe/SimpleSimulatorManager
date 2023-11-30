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
        case showVisionPro
        case showIPad
        case showIPhone
        case showWatch
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

    var showVisionPro: Bool {
        get {
            userDefaults?.bool(forKey: Keys.showVisionPro.rawValue) ?? false
        }
        set {
            userDefaults?.setValue(newValue, forKey: Keys.showVisionPro.rawValue)
        }
    }
    
    var showIPad: Bool {
        get {
            userDefaults?.bool(forKey: Keys.showIPad.rawValue) ?? false
        }
        set {
            userDefaults?.setValue(newValue, forKey: Keys.showIPad.rawValue)
        }
    }
    
    var showIPhone: Bool {
        get {
            userDefaults?.bool(forKey: Keys.showIPhone.rawValue) ?? false
        }
        set {
            userDefaults?.setValue(newValue, forKey: Keys.showIPhone.rawValue)
        }
    }
    
    var showWatch: Bool {
        get {
            userDefaults?.bool(forKey: Keys.showWatch.rawValue) ?? false
        }
        set {
            userDefaults?.setValue(newValue, forKey: Keys.showWatch.rawValue)
        }
    }
}
