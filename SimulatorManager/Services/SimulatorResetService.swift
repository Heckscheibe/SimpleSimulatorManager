//
//  SimulatorResetService.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 25.08.25.
//

import Foundation
@preconcurrency import Combine
import os

final class SimulatorResetService: Sendable {
    var didResetAllSimulators: AnyPublisher<Void, Never> {
        didResetAllSimulatorsPublisher.eraseToAnyPublisher()
    }
    
    private nonisolated(unsafe) var didResetAllSimulatorsPublisher: PassthroughSubject<Void, Never> = .init()
    
    /// Shuts down all running simulators
    func shutDownAllSimulators() async throws {
        let result = try await Task {
            try Process.execute(command: "xcrun simctl shutdown all")
        }.value
        os_log("Shut down all simulators: \(result)")
    }
    
    /// Resets all simulators to factory defaults
    func resetAllSimulators() async throws {
        let result = try await Task {
            try Process.execute(command: "xcrun simctl erase all")
        }.value
        os_log("Reset all simulators: \(result)")
        didResetAllSimulatorsPublisher.send()
    }
    
    /// Shuts down and then resets all simulators
    func shutDownAndResetAllSimulators() async throws {
        try await shutDownAllSimulators()
        try await resetAllSimulators()
    }
}
