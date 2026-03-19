//
//  SimulatorResetService.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 25.08.25.
//

import Foundation
@preconcurrency import Combine
import os

enum SimulatorDeviceAction: String, Sendable {
    case erase

    var buttonTitle: String {
        switch self {
        case .erase:
            return "Erase Simulator"
        }
    }

    var progressTitle: String {
        switch self {
        case .erase:
            return "Erasing..."
        }
    }
}

protocol SimulatorResetServing: AnyObject, Sendable {
    var didResetAllSimulators: AnyPublisher<Void, Never> { get }

    func shutDownAndEraseSimulator(deviceUdid: String) async throws
    func shutDownAllSimulators() async throws
    func resetAllSimulators() async throws
    func shutDownAndResetAllSimulators() async throws
}

final class SimulatorResetService: SimulatorResetServing, Sendable {
    var didResetAllSimulators: AnyPublisher<Void, Never> {
        didResetAllSimulatorsPublisher.eraseToAnyPublisher()
    }
    
    private nonisolated(unsafe) var didResetAllSimulatorsPublisher: PassthroughSubject<Void, Never> = .init()

    func shutDownAndEraseSimulator(deviceUdid: String) async throws {
        let shutDownResult = try await runSimctlCommand(arguments: ["shutdown", deviceUdid])
        os_log("Shut down simulator %@: %@", deviceUdid, shutDownResult)

        let eraseResult = try await runSimctlCommand(arguments: ["erase", deviceUdid])
        os_log("Erased simulator %@: %@", deviceUdid, eraseResult)
    }
    
    /// Shuts down all running simulators
    func shutDownAllSimulators() async throws {
        let result = try await runSimctlCommand(arguments: ["shutdown", "all"])
        os_log("Shut down all simulators: \(result)")
    }
    
    /// Resets all simulators to factory defaults
    func resetAllSimulators() async throws {
        let result = try await runSimctlCommand(arguments: ["erase", "all"])
        os_log("Reset all simulators: \(result)")
        didResetAllSimulatorsPublisher.send()
    }
    
    /// Shuts down and then resets all simulators
    func shutDownAndResetAllSimulators() async throws {
        try await shutDownAllSimulators()
        try await resetAllSimulators()
    }

    private func runSimctlCommand(arguments: [String]) async throws -> String {
        try await Task {
            try Process.execute(command: "/usr/bin/xcrun", arguments: ["simctl"] + arguments)
        }.value
    }
}
