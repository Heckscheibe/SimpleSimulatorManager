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

@Suite("SimulatorManagerViewModel Edge Cases")
@MainActor
struct SimulatorManagerViewModelEdgeCaseTests {
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
    
    @Test("ViewModel stays empty when publisher sends empty list after having data")
    func clearingDeviceList() async {
        // Given — start with devices
        mockDeviceManager.setMockDevices(TestDataHelpers.createMockDevices())
        try? await Task.sleep(nanoseconds: 200_000_000)
        #expect(viewModel.devices.count == 3)

        // When — clear them
        mockDeviceManager.setMockDevices([])
        try? await Task.sleep(nanoseconds: 200_000_000)

        // Then
        #expect(viewModel.devices.isEmpty)
    }
    
    // NOTE: The device-with-nil-URL scenario is a no-op (guard returns early).
    // NSWorkspace side effects cannot be asserted in unit tests, so the test
    // was removed to avoid giving false confidence.
    
    @Test("ViewModel handles rapid successive updates")
    func rapidSuccessiveUpdates() async {
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
    
    @Test("ViewModel handles large number of app changes")
    func largeNumberOfAppChanges() async {
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
    
    @Test("ViewModel forwards all publisher values without filtering duplicates")
    func duplicateAppChangesForwarded() async {
        // The ViewModel does not deduplicate — that responsibility belongs to
        // DeviceManager. Verify the ViewModel faithfully mirrors whatever the
        // publisher sends, including duplicates.
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

        // Then — ViewModel passes through without modification
        #expect(viewModel.recentAppChanges.count == 2)
        #expect(viewModel.recentInstalledApps.count == 2)
        #expect(viewModel.recentAppChanges.map(\.timestamp).count == 2)
    }
    
    @Test("ViewModel handles mixed device platforms")
    func mixedDevicePlatforms() async {
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
    
    @Test("ViewModel maintains state consistency during concurrent access")
    func concurrentAccess() async {
        // Given
        let devices = TestDataHelpers.createMockDevices()
        let mockDeviceManager = self.mockDeviceManager
        let viewModel = self.viewModel
        
        // When - Simulate concurrent access
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await MainActor.run {
                    mockDeviceManager.setMockDevices(devices)
                }
            }
            
            group.addTask {
                // Simulate UI accessing the properties
                await MainActor.run {
                    _ = viewModel.devices
                    _ = viewModel.deviceTypes
                    _ = viewModel.recentAppChanges
                }
            }
            
            group.addTask {
                // Simulate another UI access
                await MainActor.run {
                    for device in viewModel.devices {
                        viewModel.didSelectSimulatorFolder(for: device)
                    }
                }
            }
        }
        
        // Allow Combine to settle
        try? await Task.sleep(nanoseconds: 300_000_000)
        
        // Then - Should maintain consistency
        #expect(viewModel.devices.count == 3)
    }
}
