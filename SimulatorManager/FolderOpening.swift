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
    func didSelectAppPackageFolder(for app: any SimulatorApp) {
        guard let url = app.appPackageURL?.deletingLastPathComponent() else {
            return
        }
        openFolderAt(url)
    }

    func didSelectAppDocumentFolder(for app: any SimulatorApp) {
        guard let url = app.appDocumentsFolderURL else {
            return
        }
        openFolderAt(url)
    }
    
    func didSelectUserDefaultsFolder(for app: any SimulatorApp) {
        guard let url = app.appDocumentsFolderURL?.appendingPathComponent(SimulatorPaths.userDefaultsPath) else {
            return
        }
        openFolderAt(url)
    }
    
    func didSelectUserDefaultsFolder(for appGroup: AppGroup) {
        guard let url = appGroup.url?.appendingPathComponent(SimulatorPaths.userDefaultsPath) else {
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
    
    func didSelect(appGroup: AppGroup) {
        guard let url = appGroup.url else {
            return
        }
        openFolderAt(url)
    }
}
