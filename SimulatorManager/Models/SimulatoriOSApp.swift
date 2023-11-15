//
//  SimulatoriOSApp.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 17.10.23.
//

import Foundation

enum SimulatorPaths {
    static let appPackagePath = "data/Containers/Bundle/Application"
    static let appDataPath = "data/Containers/Data/Application"
}

protocol SimulatorApp: Identifiable {
    var displayName: String { get }
    var bundleIdentifier: String { get }
    var appDocumentsFolderURL: URL? { get }
    var appPackageURL: URL? { get }
    var iconName: String { get }
}

extension SimulatorApp {
    var id: String {
        bundleIdentifier
    }
}

struct SimulatoriOSApp: SimulatorApp {
    let displayName: String
    let bundleIdentifier: String
    let appDocumentsFolderURL: URL?
    let appPackageURL: URL?
    let hasWatchApp: Bool
    let iconName = "iphone.gen3"
}

struct SimulatorWatchOSApp: SimulatorApp {
    let displayName: String
    let bundleIdentifier: String
    let appDocumentsFolderURL: URL?
    let appPackageURL: URL?
    let iosAppIdentifier: String?
    let iconName = "applewatch"
}
