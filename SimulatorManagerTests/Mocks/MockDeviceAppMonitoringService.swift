//
//  MockDeviceAppMonitoringService.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 26.07.25.
//

import Foundation
@testable import SimulatorManager

class MockDeviceAppMonitoringService: DeviceAppMonitoring {
    // MARK: - Call Tracking
    
    var resetMonitoringCalled = false
    
    // MARK: - DeviceAppMonitoring Implementation
    
    func resetMonitoring() {
        resetMonitoringCalled = true
    }
}
