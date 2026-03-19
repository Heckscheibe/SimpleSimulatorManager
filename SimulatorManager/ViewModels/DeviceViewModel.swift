//
//  DeviceViewModel.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 24.11.23.
//

import Foundation
import Observation
import os

@MainActor
@Observable
class DeviceViewModel: FolderOpening {
    var device: Device
    private(set) var currentAction: SimulatorDeviceAction?
    private(set) var actionErrorMessage: String?

    @ObservationIgnored private let deviceManager: DeviceManaging
    @ObservationIgnored private let simulatorResetService: SimulatorResetServing

    init(
        device: Device,
        deviceManager: DeviceManaging,
        simulatorResetService: SimulatorResetServing
    ) {
        self.device = device
        self.deviceManager = deviceManager
        self.simulatorResetService = simulatorResetService
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

    var canEraseDevice: Bool {
        device.state == .off && !isPerformingAction
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
        let resetService = simulatorResetService

        Task { [weak self, resetService, deviceUdid, deviceName] in
            guard let self else {
                return
            }

            do {
                try await resetService.shutDownAndEraseSimulator(deviceUdid: deviceUdid)

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
