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
        self.folderMonitor = FolderMonitor(url: device.url ?? URL(fileURLWithPath: ""))
        folderMonitor.folderDidChange
            .debounce(for: 3.0, scheduler: RunLoop.main)
            .sink { [weak self] in
                self?.appfolderDidChange.send(device)
            }
            .store(in: &cancellable)
        folderMonitor.startMonitoring()
    }
}
