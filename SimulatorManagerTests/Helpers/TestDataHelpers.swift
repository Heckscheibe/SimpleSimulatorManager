//
//  TestDataHelpers.swift
//  SimulatorManagerTests
//
//  Created by AI Assistant on 26.07.25.
//

import Foundation
@testable import SimulatorManager

enum TestDataHelpers {
    // MARK: - Device Test Data
    
    static func createMockDevice(udid: String = "test-device-uuid",
                                 name: String = "Test Device",
                                 simulatorPlatform: SimulatorPlatform = .iPhone) -> Device {
        return Device(
            udid: udid,
            name: name,
            state: .running,
            simulatorPlatform: simulatorPlatform,
            osVersion: "17.0"
        )
    }
    
    static func createMockDevices() -> [Device] {
        return [
            createMockDevice(udid: "device-1", name: "iPhone 15"),
            createMockDevice(udid: "device-2", name: "iPad Pro", simulatorPlatform: .iPad),
            createMockDevice(udid: "device-3", name: "Apple Watch", simulatorPlatform: .watch)
        ]
    }
    
    // MARK: - DeviceType Test Data
    
    static func createMockDeviceType(id: String = "iPhone 15",
                                     simulatorPlatform: SimulatorPlatform = .iPhone) -> DeviceType {
        return DeviceType(id: id, simulatorPlatform: simulatorPlatform)
    }
    
    static func createMockDeviceTypes() -> [DeviceType] {
        return [
            createMockDeviceType(id: "iPhone 15", simulatorPlatform: .iPhone),
            createMockDeviceType(id: "iPad Pro", simulatorPlatform: .iPad),
            createMockDeviceType(id: "Apple Watch", simulatorPlatform: .watch)
        ]
    }
    
    // MARK: - App Test Data
    
    static func createMockApp(bundleIdentifier: String = "com.test.app",
                              displayName: String = "Test App") -> MockSimulatorApp {
        return MockSimulatorApp(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName
        )
    }
    
    // MARK: - AppChange Test Data
    
    static func createMockAppChange(app: any SimulatorApp = createMockApp(),
                                    device: Device = createMockDevice(),
                                    changeType: ChangeType = .installed,
                                    timestamp: Date = Date()) -> AppChange {
        return AppChange(
            app: app,
            device: device,
            changeType: changeType,
            timestamp: timestamp
        )
    }
    
    static func createMockAppChanges() -> [AppChange] {
        let device = createMockDevice()
        return [
            createMockAppChange(
                app: createMockApp(bundleIdentifier: "com.test.app1", displayName: "App 1"),
                device: device,
                changeType: .installed,
                timestamp: Date().addingTimeInterval(-300) // 5 minutes ago
            ),
            createMockAppChange(
                app: createMockApp(bundleIdentifier: "com.test.app2", displayName: "App 2"),
                device: device,
                changeType: .removed,
                timestamp: Date().addingTimeInterval(-60) // 1 minute ago
            )
        ]
    }
}

// MARK: - Mock SimulatorApp

struct MockSimulatorApp: SimulatorApp {
    let bundleIdentifier: String
    let displayName: String
    let url: URL? = nil
    let iconData: Data? = nil
    let appDocumentsFolderURL: URL? = nil
    let appPackageURL: URL? = nil
    let iconName: String = "app.icon"
    let hasUserDefaults: Bool = false
}
