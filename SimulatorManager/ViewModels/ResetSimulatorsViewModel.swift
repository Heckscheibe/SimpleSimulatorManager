//
//  ResetSimulatorsViewModel.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 29.08.25.
//

import Foundation
import os

class ResetSimulatorsViewModel: ObservableObject {
    @Published var isResettingSimulators = false
    
    private let deviceManager: DeviceManaging
    private let simulatorResetService: SimulatorResetService
    
    init(
        deviceManager: DeviceManaging,
        simulatorResetService: SimulatorResetService
    ) {
        self.deviceManager = deviceManager
        self.simulatorResetService = simulatorResetService
    }

    var resetButtonText: String {
        if isResettingSimulators {
            return "Resetting..."
        }

        return "Reset All Simulators (Destructive)"
    }

    var resetButtonIcon: String {
        if isResettingSimulators {
            return "hourglass"
        }

        return "arrow.clockwise"
    }
    
    @MainActor
    func resetAllSimulators() {
        guard !isResettingSimulators else {
            return
        }

        isResettingSimulators = true
        
        Task {
            do {
                try await simulatorResetService.shutDownAndResetAllSimulators()
                os_log("Successfully reset all simulators")
            } catch {
                os_log("Failed to reset simulators: \(error.localizedDescription)")
            }
            deviceManager.resetAndLoadDevices()
            await MainActor.run {
                isResettingSimulators = false
            }
        }
    }
}
