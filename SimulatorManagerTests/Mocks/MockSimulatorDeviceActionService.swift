//
//  MockSimulatorDeviceActionService.swift
//  SimulatorManagerTests
//
//  Created by Copilot on 18.03.26.
//

import Foundation
@testable import SimulatorManager

actor MockSimulatorDeviceActionService: SimulatorDeviceActionServing {
    private(set) var erasedDeviceUdid: String?
    private var error: Error?

    func setError(_ error: Error?) {
        self.error = error
    }

    func erase(deviceUdid: String) throws {
        if let error {
            throw error
        }

        erasedDeviceUdid = deviceUdid
    }
}
