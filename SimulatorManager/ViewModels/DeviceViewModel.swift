//
//  DeviceViewModel.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 24.11.23.
//

import Foundation

class DeviceViewModel: ObservableObject, FolderOpening {
    let device: Device
    
    init(device: Device) {
        self.device = device
    }
    
    func didSelect(appGroup: AppGroup) {
        guard let url = appGroup.url else {
            return
        }
        openFolderAt(url)
    }
    
    func didSelectAppPackageFolder(for app: any SimulatorApp) {
        guard let url = app.appPackageURL?.deletingLastPathComponent() else {
            return
        }
        openFolderAt(url)
    }

    func didSelectAppDocumentFolder(for app: any SimulatorApp) {
        guard let url = app.appDocumentsFolderURL else { return }
        
        openFolderAt(url)
    }
}
