//
//  Extensions.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 17.10.23.
//

import Foundation

extension FileManager {
    func directoryExistsAtURL(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        _ = fileExists(atPath: url.path, isDirectory: &isDirectory)
        return isDirectory.boolValue
    }
}
