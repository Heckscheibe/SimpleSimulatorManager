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

    /// True while no app is installed yet and we are watching the whole data folder.
    /// Once the dedicated app-packages folder appears, the owner should recreate the monitor
    /// to switch to the narrower watch.
    let isWatchingFallback: Bool

    /// Whether the underlying folder watch actually started. The owner should not cache a
    /// monitor that failed to start, so it can retry rather than hold a permanently dead one.
    private(set) var isMonitoring = false

    private let folderMonitor: FolderMonitor?
    private var cancellables: Set<AnyCancellable> = []

    init(device: Device) {
        self.device = device

        let url: URL?
        let watchingFallback: Bool
        if let appPackagesFolder = device.appPackagesFolder,
           FileManager.default.directoryExistsAtURL(appPackagesFolder) {
            url = appPackagesFolder
            watchingFallback = false
        } else {
            // The app packages folder only exists once the first app is installed.
            // Until then, watch the whole data folder so we notice the install.
            url = device.dataFolder
            watchingFallback = true
        }
        self.isWatchingFallback = watchingFallback

        guard let url else {
            folderMonitor = nil
            os_log("No folder to monitor for device %@", device.udid)
            return
        }

        // Keep the FSEvents latency small: the 3s debounce below is the coalescing window, so a
        // large FSEvents latency would stack on top of it (~4s notification delay) for no benefit.
        let monitor = FolderMonitor(url: url, latency: 0.1)
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
            isMonitoring = true
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
