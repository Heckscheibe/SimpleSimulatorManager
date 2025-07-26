//
//  MockDeviceAppMonitoringService.swift
//  SimulatorManagerTests
//
//  Created by AI Assistant on 26.07.25.
//

import Foundation
@testable import SimulatorManager

class MockDeviceAppMonitoringService: DeviceAppMonitoringServiceProtocol {
    // MARK: - Call Tracking
    
    var stopMonitoringCalled = false
    
    // MARK: - DeviceAppMonitoringServiceProtocol Implementation
    
    func stopMonitoring() {
        stopMonitoringCalled = true
    }
    
    // MARK: - Test Helper Methods
    
    func reset() {
        stopMonitoringCalled = false
    }
}
