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
    
    // MARK: - App Folder Operations
    func didSelectFolder(_ shortcut: AppContainerShortcut, for app: any SimulatorApp) {
        guard let url = shortcut.url(for: app) else {
            return
        }

        openFolderAt(url)
    }

    func didSelectFolder(_ shortcut: AppGroupShortcut, for appGroup: AppGroup) {
        guard let url = shortcut.url(for: appGroup) else {
            return
        }

        openFolderAt(url)
    }
    
    func didSelectSimulatorFolder(for device: Device) {
        guard let url = device.url else {
            return
        }

        openFolderAt(url)
    }
    
    func didSelectAppsFolder(for device: Device) {
        guard let url = device.appDataFolder else {
            return
        }

        openFolderAt(url)
    }
    
    func didSelectAppPackagesFolder(for device: Device) {
        guard let url = device.appPackagesFolder else {
            return
        }

        openFolderAt(url)
    }
}
