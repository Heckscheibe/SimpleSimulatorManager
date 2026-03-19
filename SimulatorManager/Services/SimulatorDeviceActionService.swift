//
//  SimulatorDeviceActionService.swift
//  SimulatorManager
//
//  Created by Copilot on 18.03.26.
//

import Foundation
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

protocol SimulatorDeviceActionServing: AnyObject, Sendable {
    func erase(deviceUdid: String) async throws
}

final class SimulatorDeviceActionService: SimulatorDeviceActionServing, Sendable {
    func erase(deviceUdid: String) async throws {
        let result = try await runSimctlCommand(arguments: ["erase", deviceUdid])
        os_log("Erased simulator %@: %@", deviceUdid, result)
    }

    private func runSimctlCommand(arguments: [String]) async throws -> String {
        try await Task {
            try Process.execute(command: "/usr/bin/xcrun", arguments: ["simctl"] + arguments)
        }.value
    }
}
