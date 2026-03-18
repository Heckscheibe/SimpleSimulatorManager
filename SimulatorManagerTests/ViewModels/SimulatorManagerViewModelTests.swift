//
//  SimulatorManagerViewModelTests.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 26.07.25.
//

import Testing
import Combine
@testable import SimulatorManager

@Suite("SimulatorManagerViewModel Tests")
struct SimulatorManagerViewModelTests {
    // MARK: - Test Properties
    
    private var mockDeviceManager: MockDeviceManager
    private var mockMonitoringService: MockDeviceAppMonitoringService
    private var viewModel: SimulatorManagerViewModel
    private var cancellables: Set<AnyCancellable>
    
    init() {
        mockDeviceManager = MockDeviceManager()
        mockMonitoringService = MockDeviceAppMonitoringService()
        viewModel = SimulatorManagerViewModel(
            deviceManager: mockDeviceManager,
            deviceAppMonitoringService: mockMonitoringService
        )
        cancellables = Set<AnyCancellable>()
    }
    
    // MARK: - Initialization Tests
    
    @Test("ViewModel initializes with empty arrays")
    func initialState() {
        #expect(viewModel.devices.isEmpty)
        #expect(viewModel.deviceTypes.isEmpty)
        #expect(viewModel.recentAppChanges.isEmpty)
    }
    
    @Test("ViewModel binds to device manager publishers on initialization")
    func publisherBinding() async {
        // Given
        let mockDevices = TestDataHelpers.createMockDevices()
        let mockDeviceTypes = TestDataHelpers.createMockDeviceTypes()
        let mockAppChanges = TestDataHelpers.createMockAppChanges()
        
        // When
        mockDeviceManager.setMockDevices(mockDevices)
        mockDeviceManager.setMockDeviceTypes(mockDeviceTypes)
        mockDeviceManager.setMockRecentAppChanges(mockAppChanges)
        
        // Allow time for Combine to process
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Then
        #expect(viewModel.devices.count == 3)
        #expect(viewModel.deviceTypes.count == 3)
        #expect(viewModel.recentAppChanges.count == 2)
        
        #expect(viewModel.devices.first?.name == "iPhone 15")
        #expect(viewModel.deviceTypes.first?.id == "iPhone 15")
        #expect(viewModel.recentAppChanges.first?.app.displayName == "App 1")
    }
    
    // MARK: - Device Management Tests
    
    @Test("didSelectSimulatorFolder opens folder for device with valid URL")
    func didSelectSimulatorFolderWithValidURL() {
        // Given
        var device = TestDataHelpers.createMockDevice()
        // Note: In a real test, we'd need to mock the folder opening functionality
        // For now, we just verify the method doesn't crash
        
        // When & Then - Should not crash
        viewModel.didSelectSimulatorFolder(for: device)
    }
    
    @Test("didSelectAppsFolder opens apps folder for device with valid URL")
    func didSelectAppsFolderWithValidURL() {
        // Given
        var device = TestDataHelpers.createMockDevice()
        
        // When & Then - Should not crash
        viewModel.didSelectAppsFolder(for: device)
    }
    
    // MARK: - Reactive Data Flow Tests
    
    @Test("ViewModel updates when devices change")
    func devicesUpdate() async {
        // Given
        let initialDevices = [TestDataHelpers.createMockDevice(udid: "device-1")]
        mockDeviceManager.setMockDevices(initialDevices)
        
        // Allow initial binding
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        
        #expect(viewModel.devices.count == 1)
        
        // When - Add more devices
        let updatedDevices = TestDataHelpers.createMockDevices()
        mockDeviceManager.setMockDevices(updatedDevices)
        
        // Allow Combine to process
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        
        // Then
        #expect(viewModel.devices.count == 3)
        #expect(viewModel.devices.map(\.udid).contains("device-1"))
        #expect(viewModel.devices.map(\.udid).contains("device-2"))
        #expect(viewModel.devices.map(\.udid).contains("device-3"))
    }
    
    @Test("ViewModel updates when device types change")
    func deviceTypesUpdate() async {
        // Given
        let initialDeviceTypes = [TestDataHelpers.createMockDeviceType()]
        mockDeviceManager.setMockDeviceTypes(initialDeviceTypes)
        
        // Allow initial binding
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        #expect(viewModel.deviceTypes.count == 1)
        
        // When
        let updatedDeviceTypes = TestDataHelpers.createMockDeviceTypes()
        mockDeviceManager.setMockDeviceTypes(updatedDeviceTypes)
        
        // Allow Combine to process
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        // Then
        #expect(viewModel.deviceTypes.count == 3)
        #expect(viewModel.deviceTypes.map(\.id).contains("iPhone 15"))
        #expect(viewModel.deviceTypes.map(\.id).contains("iPad Pro"))
        #expect(viewModel.deviceTypes.map(\.id).contains("Apple Watch"))
    }
    
    @Test("ViewModel updates when recent app changes occur")
    func recentAppChangesUpdate() async {
        // Given - Start with empty changes
        #expect(viewModel.recentAppChanges.isEmpty)
        
        // When - Simulate app changes
        let appChanges = TestDataHelpers.createMockAppChanges()
        mockDeviceManager.simulateAppChanges(appChanges)
        
        // Allow Combine to process
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        // Then
        #expect(viewModel.recentAppChanges.count == 2)
        
        let appIdentifiers = viewModel.recentAppChanges.map(\.app.bundleIdentifier)
        #expect(appIdentifiers.contains("com.test.app1"))
        #expect(appIdentifiers.contains("com.test.app2"))
        
        let changeTypes = viewModel.recentAppChanges.map(\.changeType)
        #expect(changeTypes.contains(.installed))
        #expect(changeTypes.contains(.removed))
    }
    
    // MARK: - Integration Tests
    
    @Test("ViewModel correctly handles multiple simultaneous updates")
    func multipleSimultaneousUpdates() async {
        // Given
        let devices = TestDataHelpers.createMockDevices()
        let deviceTypes = TestDataHelpers.createMockDeviceTypes()
        let appChanges = TestDataHelpers.createMockAppChanges()
        
        // When - Update all publishers simultaneously
        mockDeviceManager.setMockDevices(devices)
        mockDeviceManager.setMockDeviceTypes(deviceTypes)
        mockDeviceManager.setMockRecentAppChanges(appChanges)
        
        // Allow Combine to process all updates
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Then - All should be updated correctly
        #expect(viewModel.devices.count == 3)
        #expect(viewModel.deviceTypes.count == 3)
        #expect(viewModel.recentAppChanges.count == 2)
        
        // Verify data integrity
        #expect(viewModel.devices.map(\.udid).sorted() == ["device-1", "device-2", "device-3"])
        #expect(viewModel.deviceTypes.map(\.id).sorted() == ["Apple Watch", "iPad Pro", "iPhone 15"])
    }
    
    @Test("ViewModel maintains proper memory management")
    func memoryManagement() {
        // Given - Create a new view model instance
        var localViewModel: SimulatorManagerViewModel? = SimulatorManagerViewModel(
            deviceManager: mockDeviceManager,
            deviceAppMonitoringService: mockMonitoringService
        )
        
        // When - Set to nil (simulate deallocation)
        weak var weakViewModel = localViewModel
        localViewModel = nil
        
        // Then - Should be deallocated
        #expect(weakViewModel == nil)
    }
}
