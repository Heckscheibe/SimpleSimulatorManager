//
//  DeviceViewModel.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 24.11.23.
//

import Foundation
import os

@MainActor
class DeviceViewModel: ObservableObject, FolderOpening {
    @Published var device: Device
    @Published private(set) var currentAction: SimulatorDeviceAction?
    @Published private(set) var actionErrorMessage: String?

    private let deviceManager: DeviceManaging
    private let simulatorDeviceActionService: SimulatorDeviceActionServing

    init(
        device: Device,
        deviceManager: DeviceManaging,
        simulatorDeviceActionService: SimulatorDeviceActionServing
    ) {
        self.device = device
        self.deviceManager = deviceManager
        self.simulatorDeviceActionService = simulatorDeviceActionService
    }
    
    // MARK: - Device Properties
    
    var hasAppsInstalled: Bool {
        device.hasAppsInstalled
    }
    
    var osVersion: String {
        device.osVersion
    }
    
    var apps: [any SimulatorApp] {
        device.apps
    }
    
    var appGroups: [AppGroup] {
        device.appGroups
    }

    var stateDescription: String {
        device.state.stateDescription
    }

    var isPerformingAction: Bool {
        currentAction != nil
    }

    var currentActionTitle: String {
        currentAction?.progressTitle ?? ""
    }
    
    // MARK: - Folder Existence Checks
    
    var hasAppsFolder: Bool {
        guard let url = device.appDataFolder else {
            return false
        }

        return FileManager.default.fileExists(atPath: url.path)
    }
    
    var hasAppPackagesFolder: Bool {
        guard let url = device.appPackagesFolder else {
            return false
        }

        return FileManager.default.fileExists(atPath: url.path)
    }

    func eraseDevice() {
        performAction(.erase)
    }
}

private extension DeviceViewModel {
    func performAction(_ action: SimulatorDeviceAction) {
        guard !isPerformingAction else {
            return
        }

        actionErrorMessage = nil
        currentAction = action

        let deviceUdid = device.udid
        let deviceName = device.name
        let actionService = simulatorDeviceActionService

        Task { [weak self, actionService, deviceUdid, deviceName] in
            guard let self else {
                return
            }

            do {
                try await actionService.erase(deviceUdid: deviceUdid)

                deviceManager.updateSpecificDevice(device)

                guard let refreshedDevice = deviceManager.getDevice(withUdid: deviceUdid) else {
                    throw NSError(
                        domain: "SimulatorDeviceAction",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to refresh \(deviceName) after \(action.buttonTitle.lowercased())."]
                    )
                }

                self.device = refreshedDevice
                self.currentAction = nil
            } catch {
                os_log("Failed to perform %@ for %@: %@", action.rawValue, deviceUdid, error.localizedDescription)

                self.currentAction = nil
                self.actionErrorMessage = error.localizedDescription
            }
        }
    }
}
