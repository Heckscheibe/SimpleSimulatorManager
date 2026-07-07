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

    /// The most recent device snapshot. Updated in place after each refresh (see `update(device:)`)
    /// so the change is emitted with fresh state without recreating the underlying FSEvents watch.
    private(set) var device: Device

    /// True while no app is installed yet and we are watching the whole data folder recursively.
    /// Once the dedicated app-packages folder appears, the owner should recreate the monitor to
    /// switch to the cheaper non-recursive watch.
    let isWatchingFallback: Bool

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
        self.isWatchingFallback = recursive

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

    /// Refresh the captured device snapshot without touching the underlying folder watch,
    /// so the next emitted change diffs against the latest state.
    func update(device: Device) {
        self.device = device
    }

    deinit {
        try? folderMonitor?.stopMonitoring()
    }
}
