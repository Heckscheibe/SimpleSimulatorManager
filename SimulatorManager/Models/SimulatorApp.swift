//
//  SimulatorApp.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 17.10.23.
//

import Foundation

protocol SimulatorApp: Identifiable {
    var displayName: String { get }
    var bundleIdentifier: String { get }
    var appDocumentsFolderURL: URL? { get }
    var appPackageURL: URL? { get }
    var iconName: String { get }
    var hasUserDefaults: Bool { get }
}

extension SimulatorApp {
    var id: String {
        bundleIdentifier
    }
}

class SimulatoriOSApp: SimulatorApp {
    let displayName: String
    let bundleIdentifier: String
    let appDocumentsFolderURL: URL?
    let appPackageURL: URL?
    let hasUserDefaults: Bool
    let iconName = "iphone.gen3"
    
    let hasWatchApp: Bool
    
    init(displayName: String,
         bundleIdentifier: String,
         appDocumentsFolderURL: URL?,
         appPackageURL: URL?,
         hasWatchApp: Bool,
         hasUserDefaults: Bool) {
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.appDocumentsFolderURL = appDocumentsFolderURL
        self.appPackageURL = appPackageURL
        self.hasWatchApp = hasWatchApp
        self.hasUserDefaults = hasUserDefaults
    }
}

class SimulatorWatchOSApp: SimulatorApp {
    let displayName: String
    let bundleIdentifier: String
    let appDocumentsFolderURL: URL?
    let hasUserDefaults: Bool
    let appPackageURL: URL?
    let iconName = "applewatch"
    
    let companioniOSAppBundleIdentifier: String?
    
    init(displayName: String,
         bundleIdentifier: String,
         appDocumentsFolderURL: URL?,
         appPackageURL: URL?,
         hasUserDefaults: Bool,
         companioniOSAppBundleIdentifier: String?) {
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.appDocumentsFolderURL = appDocumentsFolderURL
        self.appPackageURL = appPackageURL
        self.hasUserDefaults = hasUserDefaults
        self.companioniOSAppBundleIdentifier = companioniOSAppBundleIdentifier
    }
}
