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
@MainActor
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
    
    // NOTE: didSelectSimulatorFolder / didSelectAppsFolder call through to
    // NSWorkspace which cannot be verified in unit tests without an AppKit mock.
    // Those methods are thin wrappers (guard + openFolderAt) and are covered
    // implicitly by FolderOpening's default implementation.
    
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
    
    @Test("ViewModel forwards publisher values to both recentAppChanges and recentInstalledApps")
    func recentAppChangesUpdate() async {
        // Given - Start with empty changes
        #expect(viewModel.recentAppChanges.isEmpty)
        #expect(viewModel.recentInstalledApps.isEmpty)

        // When - Push values directly through the publisher
        let appChanges = TestDataHelpers.createMockAppChanges()
        mockDeviceManager.setMockRecentAppChanges(appChanges)

        // Allow Combine to process
        try? await Task.sleep(nanoseconds: 200_000_000)

        // Then - Both properties mirror the publisher value (ViewModel applies no filtering)
        #expect(viewModel.recentInstalledApps.count == appChanges.count)
        #expect(viewModel.recentAppChanges.count == appChanges.count)

        let appIdentifiers = viewModel.recentInstalledApps.map(\.app.bundleIdentifier)
        #expect(appIdentifiers.contains("com.test.app1"))
        #expect(appIdentifiers.contains("com.test.app2"))
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

    @Test("ViewModel reuses cached device view models and refreshes their device")
    func cachedDeviceViewModels() async throws {
        let initialDevice = TestDataHelpers.createMockDevice(udid: "device-1", name: "Initial Device", state: .off)
        let refreshedDevice = TestDataHelpers.createMockDevice(udid: "device-1", name: "Refreshed Device", state: .running)

        mockDeviceManager.setMockDevices([initialDevice])
        try await Task.sleep(nanoseconds: 200_000_000)

        let initialViewModel = viewModel.makeDeviceViewModel(for: initialDevice)

        mockDeviceManager.setMockDevices([refreshedDevice])
        try await Task.sleep(nanoseconds: 200_000_000)

        let refreshedViewModel = viewModel.makeDeviceViewModel(for: refreshedDevice)

        #expect(initialViewModel === refreshedViewModel)
        #expect(refreshedViewModel.device.name == "Refreshed Device")
        #expect(refreshedViewModel.device.state == .running)
    }
}
