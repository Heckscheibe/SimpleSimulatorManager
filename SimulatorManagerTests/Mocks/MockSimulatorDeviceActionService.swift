//
//  MockSimulatorDeviceActionService.swift
//  SimulatorManagerTests
//
//  Created by Copilot on 18.03.26.
//

import Foundation
@preconcurrency import Combine
@testable import SimulatorManager

actor MockSimulatorDeviceActionService: SimulatorResetServing {
    nonisolated var didResetAllSimulators: AnyPublisher<Void, Never> {
        didResetAllSimulatorsSubject.eraseToAnyPublisher()
    }

    private(set) var erasedDeviceUdid: String?
    private(set) var shutDownDeviceUdid: String?
    private var error: Error?
    private nonisolated(unsafe) let didResetAllSimulatorsSubject = PassthroughSubject<Void, Never>()

    func setError(_ error: Error?) {
        self.error = error
    }

    func shutDownAndEraseSimulator(deviceUdid: String) throws {
        if let error {
            throw error
        }

        shutDownDeviceUdid = deviceUdid
        erasedDeviceUdid = deviceUdid
    }

    func shutDownAllSimulators() throws {}

    func resetAllSimulators() throws {
        didResetAllSimulatorsSubject.send()
    }

    func shutDownAndResetAllSimulators() throws {
        didResetAllSimulatorsSubject.send()
    }
}
