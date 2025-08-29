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
    
    private let simulatorResetService = SimulatorResetService()
    
    @MainActor func resetAllSimulators() {
        guard !isResettingSimulators else { return }
        
        isResettingSimulators = true
        
        Task {
            do {
                try await simulatorResetService.shutDownAndResetAllSimulators()
                os_log("Successfully reset all simulators")
            } catch {
                os_log("Failed to reset simulators: \(error.localizedDescription)")
            }
            
            await MainActor.run {
                isResettingSimulators = false
            }
        }
    }
}
