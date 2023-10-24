//
//  SimulatorApp.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 17.10.23.
//

import Foundation

struct SimulatorApp {
    static let appPackagePath = "data/Containers/Bundle/Application"
    static let appDataPath = "data/Containers/Data/Application"
    
    let displayName: String
    let bundleIdentifier: String
    let appDocumentsFolderURL: URL?
    let appPackageURL: URL?
    let hasWatchApp: Bool
}

extension SimulatorApp: Identifiable {
    var id: String {
        bundleIdentifier
    }
}
