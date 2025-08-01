//
//  SimulatorManagerViewModelEdgeCaseTests.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 26.07.25.
//

import Foundation
import Testing
import Combine
@testable import SimulatorManager

@Suite("SimulatorManagerViewModel Edge Cases") struct SimulatorManagerViewModelEdgeCaseTests {
    private var mockDeviceManager: MockDeviceManager
    private var mockMonitoringService: MockDeviceAppMonitoringService
    private var viewModel: SimulatorManagerViewModel
    
    init() {
        mockDeviceManager = MockDeviceManager()
        mockMonitoringService = MockDeviceAppMonitoringService()
        viewModel = SimulatorManagerViewModel(
            deviceManager: mockDeviceManager,
            deviceAppMonitoringService: mockMonitoringService
        )
    }
    
    // MARK: - Edge Case Tests
    
    @Test("ViewModel handles empty device list gracefully") func testEmptyDeviceList() async {
        // Given
        mockDeviceManager.setMockDevices([])
        
        // Allow Combine to process
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        // Then
        #expect(viewModel.devices.isEmpty)
    }
    
    @Test("ViewModel handles device with nil URL") func testDeviceWithNilURL() {
        // Given
        var device = TestDataHelpers.createMockDevice()
        // Device URL is nil by default in our test helper
        
        // When & Then - Should not crash
        viewModel.didSelectSimulatorFolder(for: device)
        viewModel.didSelectAppsFolder(for: device)
    }
    
    @Test("ViewModel handles rapid successive updates") func testRapidSuccessiveUpdates() async {
        // Given
        let devices1 = [TestDataHelpers.createMockDevice(udid: "device-1")]
        let devices2 = TestDataHelpers.createMockDevices()
        let devices3 = [TestDataHelpers.createMockDevice(udid: "device-final")]
        
        // When - Send rapid updates
        mockDeviceManager.setMockDevices(devices1)
        mockDeviceManager.setMockDevices(devices2)
        mockDeviceManager.setMockDevices(devices3)
        
        // Allow Combine to process
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        
        // Then - Should have the final state
        #expect(viewModel.devices.count == 1)
        #expect(viewModel.devices.first?.udid == "device-final")
    }
    
    @Test("ViewModel handles large number of app changes") func testLargeNumberOfAppChanges() async {
        // Given - Create many app changes
        let device = TestDataHelpers.createMockDevice()
        var appChanges: [AppChange] = []
        
        for index in 0 ..< 100 {
            let app = TestDataHelpers.createMockApp(
                bundleIdentifier: "com.test.app\(index)",
                displayName: "App \(index)"
            )
            let change = TestDataHelpers.createMockAppChange(
                app: app,
                device: device,
                changeType: index % 2 == 0 ? .installed : .removed
            )
            appChanges.append(change)
        }
        
        // When
        mockDeviceManager.setMockRecentAppChanges(appChanges)
        
        // Allow Combine to process
        try? await Task.sleep(nanoseconds: 300_000_000)
        
        // Then
        #expect(viewModel.recentAppChanges.count == 100)
        
        // Verify data integrity
        let bundleIds = viewModel.recentAppChanges.map(\.app.bundleIdentifier)
        #expect(bundleIds.contains("com.test.app0"))
        #expect(bundleIds.contains("com.test.app99"))
    }
    
    @Test("ViewModel handles duplicate app changes") func testDuplicateAppChanges() async {
        // Given
        let app = TestDataHelpers.createMockApp(bundleIdentifier: "com.duplicate.app")
        let device = TestDataHelpers.createMockDevice()
        
        let change1 = TestDataHelpers.createMockAppChange(
            app: app,
            device: device,
            changeType: .installed,
            timestamp: Date().addingTimeInterval(-60)
        )
        
        let change2 = TestDataHelpers.createMockAppChange(
            app: app,
            device: device,
            changeType: .installed,
            timestamp: Date()
        )
        
        // When
        mockDeviceManager.setMockRecentAppChanges([change1, change2])
        
        // Allow Combine to process
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        // Then - Should handle duplicates appropriately
        #expect(viewModel.recentAppChanges.count == 2)
        
        // Verify both changes are present (mock doesn't deduplicate)
        let timestamps = viewModel.recentAppChanges.map(\.timestamp)
        #expect(timestamps.count == 2)
    }
    
    @Test("ViewModel handles mixed device platforms") func testMixedDevicePlatforms() async {
        // Given
        let devices = [
            TestDataHelpers.createMockDevice(udid: "ios-device", simulatorPlatform: .iPhone),
            TestDataHelpers.createMockDevice(udid: "watchos-device", simulatorPlatform: .watch),
            TestDataHelpers.createMockDevice(udid: "tvos-device", simulatorPlatform: .appleTV)
        ]
        
        // When
        mockDeviceManager.setMockDevices(devices)
        
        // Allow Combine to process
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        // Then
        #expect(viewModel.devices.count == 3)
        
        let platforms = viewModel.devices.map(\.simulatorPlatform)
        #expect(platforms.contains(.iPhone))
        #expect(platforms.contains(.watch))
        #expect(platforms.contains(.appleTV))
    }
    
    @Test("ViewModel maintains state consistency during concurrent access") func testConcurrentAccess() async {
        // Given
        let devices = TestDataHelpers.createMockDevices()
        
        // When - Simulate concurrent access
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                self.mockDeviceManager.setMockDevices(devices)
            }
            
            group.addTask {
                // Simulate UI accessing the properties
                _ = self.viewModel.devices
                _ = self.viewModel.deviceTypes
                _ = self.viewModel.recentAppChanges
            }
            
            group.addTask {
                // Simulate another UI access
                for device in self.viewModel.devices {
                    self.viewModel.didSelectSimulatorFolder(for: device)
                }
            }
        }
        
        // Allow Combine to settle
        try? await Task.sleep(nanoseconds: 300_000_000)
        
        // Then - Should maintain consistency
        #expect(viewModel.devices.count == 3)
    }
}
