//
//  MockDeviceAppMonitoringService.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 26.07.25.
//

import Foundation
@testable import SimulatorManager
@testable import SimulatorCore

/// Stands in for `DeviceAppMonitoringService` so a view model under test starts no FSEvents watches.
class MockDeviceAppMonitoringService: DeviceAppMonitoring {}
