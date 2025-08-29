//
//  SimulatorResetService.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 25.08.25.
//

import Foundation
import os

class SimulatorResetService {
    /// Shuts down all running simulators
    func shutDownAllSimulators() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try Process.execute(command: "xcrun simctl shutdown all")
                    os_log("Shut down all simulators: \(result)")
                    continuation.resume()
                } catch {
                    os_log("Failed to shut down simulators: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Resets all simulators to factory defaults
    func resetAllSimulators() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try Process.execute(command: "xcrun simctl erase all")
                    os_log("Reset all simulators: \(result)")
                    continuation.resume()
                } catch {
                    os_log("Failed to reset simulators: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Shuts down and then resets all simulators
    func shutDownAndResetAllSimulators() async throws {
        try await shutDownAllSimulators()
        try await resetAllSimulators()
    }
}
