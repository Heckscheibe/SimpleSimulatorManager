//
//  AppFolderMonitor.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 15.12.23.
//

import Foundation
import Combine

class AppFolderMonitor {
    let appfolderDidChange: PassthroughSubject<Device, Never> = .init()

    private let device: Device
    private let folderMonitor: FolderMonitor
    private var cancellable: [AnyCancellable] = []

    init(device: Device) {
        self.device = device
        let url: URL?
        let recursive: Bool
        if FileManager.default.fileExists(atPath: device.appPackagesFolder?.path ?? "") {
            url = device.appPackagesFolder
            recursive = false
        } else {
            url = device.dataFolder
            recursive = true
        }
        self.folderMonitor = FolderMonitor(url: url ?? URL(fileURLWithPath: ""),
                                           recursive: recursive)
        folderMonitor.folderDidChange
            .debounce(for: 3.0, scheduler: DispatchQueue.main)
            .sink { [weak self] in
                self?.appfolderDidChange.send(device)
            }
            .store(in: &cancellable)
        do {
            try folderMonitor.startMonitoring()
        } catch {
            print(error)
        }
    }
    
    deinit {
        try? folderMonitor.stopMonitoring()
    }
}
