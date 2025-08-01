//
//  MockDeviceManager.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 26.07.25.
//

import Foundation
import Combine
@testable import SimulatorManager

class MockDeviceManager: DeviceManagerProtocol {
    // MARK: - Publishers
    
    private let deviceTypesSubject = CurrentValueSubject<[DeviceType], Never>([])
    private let devicesSubject = CurrentValueSubject<[Device], Never>([])
    private let recentInstalledAppsSubject = CurrentValueSubject<[AppChange], Never>([])
    
    var deviceTypes: AnyPublisher<[DeviceType], Never> {
        deviceTypesSubject.eraseToAnyPublisher()
    }
    
    var devices: AnyPublisher<[Device], Never> {
        devicesSubject.eraseToAnyPublisher()
    }
    
    var recentInstalledApps: AnyPublisher<[AppChange], Never> {
        recentInstalledAppsSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Mock Data
    
    private var mockDevices: [Device] = []
    private var mockDeviceTypes: [DeviceType] = []
    private var mockRecentAppChanges: [AppChange] = []
    private var mockRecentInstalledApps: [AppChange] = []
    
    // MARK: - Call Tracking
    
    var updateDevicesCalled = false
    var updateSpecificDeviceCalled = false
    var getDeviceCalled = false
    var addAppChangesCalled = false
    
    var lastUpdatedDevice: Device?
    var lastQueriedUdid: String?
    var lastAddedChanges: [AppChange] = []
    
    // MARK: - Mock Setup Methods
    
    func setMockDevices(_ devices: [Device]) {
        mockDevices = devices
        devicesSubject.send(devices)
    }
    
    func setMockDeviceTypes(_ deviceTypes: [DeviceType]) {
        mockDeviceTypes = deviceTypes
        deviceTypesSubject.send(deviceTypes)
    }
    
    func setMockRecentAppChanges(_ changes: [AppChange]) {
        mockRecentAppChanges = changes
        recentAppChangesSubject.send(changes)
    }
    
    func setMockRecentInstalledApps(_ apps: [AppChange]) {
        mockRecentInstalledApps = apps
        recentInstalledAppsSubject.send(apps)
    }
    
    func simulateAppChanges(_ changes: [AppChange]) {
        mockRecentAppChanges.append(contentsOf: changes)
        recentAppChangesSubject.send(mockRecentAppChanges)
        
        // Simulate the lifecycle management for installed apps
        var currentInstalled = mockRecentInstalledApps
        for change in changes {
            let appKey = "\(change.app.bundleIdentifier)-\(change.device.udid)"
            switch change.changeType {
            case .installed:
                currentInstalled.removeAll { existing in
                    let existingKey = "\(existing.app.bundleIdentifier)-\(existing.device.udid)"
                    return existingKey == appKey
                }
                currentInstalled.append(change)
            case .removed:
                currentInstalled.removeAll { existing in
                    let existingKey = "\(existing.app.bundleIdentifier)-\(existing.device.udid)"
                    return existingKey == appKey
                }
            }
        }
        mockRecentInstalledApps = currentInstalled
        recentInstalledAppsSubject.send(currentInstalled)
    }
    
    // MARK: - DeviceManagerProtocol Implementation
    
    func updateDevices() {
        updateDevicesCalled = true
    }
    
    func updateSpecificDevice(_ updatedDevice: Device) {
        updateSpecificDeviceCalled = true
        lastUpdatedDevice = updatedDevice
        
        // Update the device in mock data
        if let index = mockDevices.firstIndex(where: { $0.udid == updatedDevice.udid }) {
            mockDevices[index] = updatedDevice
            devicesSubject.send(mockDevices)
        }
    }
    
    func getDevice(withUdid udid: String) -> Device? {
        getDeviceCalled = true
        lastQueriedUdid = udid
        return mockDevices.first { $0.udid == udid }
    }
    
    func addAppChanges(_ changes: [AppChange]) {
        addAppChangesCalled = true
        lastAddedChanges = changes
        mockRecentAppChanges.append(contentsOf: changes)
        recentAppChangesSubject.send(mockRecentAppChanges)
    }
    
    // MARK: - Test Helper Methods
    
    func reset() {
        updateDevicesCalled = false
        updateSpecificDeviceCalled = false
        getDeviceCalled = false
        addAppChangesCalled = false
        lastUpdatedDevice = nil
        lastQueriedUdid = nil
        lastAddedChanges = []
        mockDevices = []
        mockDeviceTypes = []
        mockRecentAppChanges = []
    }
}
