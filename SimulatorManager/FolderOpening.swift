//
//  FolderOpening.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 24.11.23.
//

import Foundation
import AppKit

protocol FolderOpening {}

extension FolderOpening {
    func openFolderAt(_ url: URL) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }
}
