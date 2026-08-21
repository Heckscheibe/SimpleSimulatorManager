//
//  ResetSimulatorsViewModel.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 29.08.25.
//

import Foundation
import Observation
import os

@MainActor
@Observable
class ResetSimulatorsViewModel {
    var isResettingSimulators = false
    
    @ObservationIgnored private let deviceManager: DeviceManaging
    @ObservationIgnored private let simulatorResetService: SimulatorResetServing
    
    init(
        deviceManager: DeviceManaging,
        simulatorResetService: SimulatorResetServing
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
            // Await the reload: it runs off the main thread, and until it publishes the menu still
            // lists every app that was just erased. Dropping the indicator first would make that
            // stale listing look like the reset silently failed.
            await deviceManager.resetAndLoadDevices()
            isResettingSimulators = false
        }
    }
}
