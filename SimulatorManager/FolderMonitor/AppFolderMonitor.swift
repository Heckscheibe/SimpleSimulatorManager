//
//  AppFolderMonitor.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 15.12.23.
//

import Combine
import Foundation
import os

final class AppFolderMonitor {
    let appfolderDidChange: PassthroughSubject<Device, Never> = .init()

    private let device: Device
    private let folderMonitor: FolderMonitor?
    private var cancellables: Set<AnyCancellable> = []

    init(device: Device) {
        self.device = device

        let url: URL?
        let recursive: Bool
        if let appPackagesFolder = device.appPackagesFolder,
           FileManager.default.directoryExistsAtURL(appPackagesFolder) {
            url = appPackagesFolder
            recursive = false
        } else {
            // The app packages folder only exists once the first app is installed.
            // Until then, watch the whole data folder recursively so we notice the install.
            url = device.dataFolder
            recursive = true
        }

        guard let url else {
            folderMonitor = nil
            os_log("No folder to monitor for device %@", device.udid)
            return
        }

        let monitor = FolderMonitor(url: url, recursive: recursive)
        folderMonitor = monitor

        monitor.folderDidChange
            .debounce(for: 3.0, scheduler: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else {
                    return
                }

                self.appfolderDidChange.send(self.device)
            }
            .store(in: &cancellables)

        do {
            try monitor.startMonitoring()
        } catch {
            os_log("Failed to start monitoring %@ for device %@: %@",
                   url.path,
                   device.udid,
                   String(describing: error))
        }
    }

    deinit {
        try? folderMonitor?.stopMonitoring()
    }
}
