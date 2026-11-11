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
    /// What a monitor watches for a device, and how narrowly.
    struct WatchTarget: Equatable {
        /// The folder handed to FSEvents. It must exist when the watch starts to be useful.
        let url: URL

        /// Set for the fallback watch only: events are forwarded when they concern this folder,
        /// which does not exist yet, and dropped when they concern the rest of `url`.
        let relevantFolder: URL?

        var isFallback: Bool {
            relevantFolder != nil
        }
    }

    let appfolderDidChange: PassthroughSubject<Device, Never> = .init()

    /// The most recent device snapshot. Updated in place after each refresh (see `update(device:)`)
    /// so the change is emitted with fresh state without recreating the underlying FSEvents watch.
    private(set) var device: Device

    /// True while no app is installed yet and we are watching the data folder, filtered to the
    /// app-packages folder. Once that folder appears, the owner should recreate the monitor
    /// to switch to the direct, unfiltered watch.
    let isWatchingFallback: Bool

    /// Whether the underlying folder watch actually started. The owner should not cache a
    /// monitor that failed to start, so it can retry rather than hold a permanently dead one.
    private(set) var isMonitoring = false

    private let folderMonitor: FolderMonitor?
    private var cancellables: Set<AnyCancellable> = []

    init(device: Device) {
        self.device = device

        let target = Self.watchTarget(for: device)
        self.isWatchingFallback = target?.isFallback ?? true

        guard let target else {
            folderMonitor = nil
            os_log("No folder to monitor for device %@", device.udid)
            return
        }

        let url = target.url
        let eventFilter = target.relevantFolder.flatMap {
            FolderEventPathFilter(watchedRoot: target.url, relevantFolder: $0)
        }
        if target.isFallback, eventFilter == nil {
            os_log("Watching %@ unfiltered for device %@; installs may be reported late while it is busy",
                   url.path,
                   device.udid)
        }

        // Keep the FSEvents latency small: the 3s debounce below is the coalescing window, so a
        // large FSEvents latency would stack on top of it (~4s notification delay) for no benefit.
        let monitor = FolderMonitor(url: url, latency: 0.1, eventFilter: eventFilter)
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

    /// Chooses what to watch for `device`.
    ///
    /// The app-packages folder (`data/Containers/Bundle/Application`) is watched directly when it
    /// exists. It is only created by the first install, so a device with no apps, such as one just
    /// erased, has to be watched from its `data` folder instead. That folder is the wrong thing to
    /// debounce on: a booted simulator changes hundreds of paths under it every couple of seconds,
    /// each restarting the debounce, so the install it should report would wait until the simulator
    /// goes quiet. No narrower folder helps either, because `Containers/Bundle` does not exist before
    /// the first install and `Containers` holds the system apps' busy data containers. The fallback
    /// therefore watches `data` but only reacts to events about the app-packages folder.
    static func watchTarget(for device: Device, fileManager: FileManager = .default) -> WatchTarget? {
        guard let appPackagesFolder = device.appPackagesFolder,
              let dataFolder = device.dataFolder else {
            return nil
        }

        if fileManager.directoryExistsAtURL(appPackagesFolder) {
            return WatchTarget(url: appPackagesFolder, relevantFolder: nil)
        }

        return WatchTarget(url: dataFolder, relevantFolder: appPackagesFolder)
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
