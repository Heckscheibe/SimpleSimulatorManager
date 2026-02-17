//
//  TestDataHelpers.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 26.07.25.
//

import Foundation
@testable import SimulatorManager

enum TestDataHelpers {
    // MARK: - Device Test Data
    
    static func createMockDevice(
        udid: String = "test-device-uuid",
        name: String = "Test Device",
        state: DeviceState = .running,
        simulatorPlatform: SimulatorPlatform = .iPhone,
        osVersion: String = "17.0"
    ) -> Device {
        return Device(
            udid: udid,
            name: name,
            state: state,
            simulatorPlatform: simulatorPlatform,
            osVersion: osVersion
        )
    }
    
    static func createMockDevices() -> [Device] {
        return [
            createMockDevice(udid: "device-1", name: "iPhone 15", simulatorPlatform: .iPhone, osVersion: "17.2"),
            createMockDevice(udid: "device-2", name: "iPad Pro", simulatorPlatform: .iPad, osVersion: "17.2"),
            createMockDevice(udid: "device-3", name: "Apple Watch", simulatorPlatform: .watch, osVersion: "10.2")
        ]
    }
    
    static func createiPhoneDevice(
        udid: String = "iphone-device",
        name: String = "iPhone 15 Pro",
        state: DeviceState = .running
    ) -> Device {
        return createMockDevice(
            udid: udid,
            name: name,
            state: state,
            simulatorPlatform: .iPhone,
            osVersion: "17.2"
        )
    }
    
    static func createiPadDevice(
        udid: String = "ipad-device",
        name: String = "iPad Pro",
        state: DeviceState = .running
    ) -> Device {
        return createMockDevice(
            udid: udid,
            name: name,
            state: state,
            simulatorPlatform: .iPad,
            osVersion: "17.2"
        )
    }
    
    static func createWatchDevice(
        udid: String = "watch-device",
        name: String = "Apple Watch Series 9",
        state: DeviceState = .running
    ) -> Device {
        return createMockDevice(
            udid: udid,
            name: name,
            state: state,
            simulatorPlatform: .watch,
            osVersion: "10.2"
        )
    }
    
    static func createAppleTVDevice(
        udid: String = "appletv-device",
        name: String = "Apple TV 4K",
        state: DeviceState = .running
    ) -> Device {
        return createMockDevice(
            udid: udid,
            name: name,
            state: state,
            simulatorPlatform: .appleTV,
            osVersion: "17.2"
        )
    }
    
    static func createVisionProDevice(
        udid: String = "visionpro-device",
        name: String = "Apple Vision Pro",
        state: DeviceState = .running
    ) -> Device {
        return createMockDevice(
            udid: udid,
            name: name,
            state: state,
            simulatorPlatform: .visionPro,
            osVersion: "1.0"
        )
    }
    
    static func createOfflineDevice(
        udid: String = "offline-device",
        name: String = "Offline Device"
    ) -> Device {
        return createMockDevice(
            udid: udid,
            name: name,
            state: .off,
            simulatorPlatform: .iPhone,
            osVersion: "17.0"
        )
    }
    
    // MARK: - Device Collection Factory Methods
    
    static func createMixedPlatformDevices() -> [Device] {
        return [
            createiPhoneDevice(udid: "iphone-1", name: "iPhone 15"),
            createiPadDevice(udid: "ipad-1", name: "iPad Pro"),
            createWatchDevice(udid: "watch-1", name: "Apple Watch Series 9"),
            createAppleTVDevice(udid: "appletv-1", name: "Apple TV 4K"),
            createVisionProDevice(udid: "visionpro-1", name: "Apple Vision Pro")
        ]
    }
    
    static func createMixedStateDevices() -> [Device] {
        return [
            createiPhoneDevice(udid: "iphone-running", name: "Running iPhone", state: .running),
            createiPhoneDevice(udid: "iphone-off", name: "Offline iPhone", state: .off),
            createiPadDevice(udid: "ipad-running", name: "Running iPad", state: .running),
            createWatchDevice(udid: "watch-off", name: "Offline Watch", state: .off)
        ]
    }
    
    static func createLargeDeviceList(count: Int = 50) -> [Device] {
        return (0 ..< count).map { index in
            let platforms: [SimulatorPlatform] = [.iPhone, .iPad, .watch, .appleTV, .visionPro]
            let platform = platforms[index % platforms.count]
            return createMockDevice(
                udid: "device-\(index)",
                name: "Test Device \(index)",
                simulatorPlatform: platform
            )
        }
    }
    
    // MARK: - DeviceType Test Data
    
    static func createMockDeviceType(
        id: String = "iPhone 15",
        simulatorPlatform: SimulatorPlatform = .iPhone
    ) -> DeviceType {
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
    
    static func createMockApp(
        bundleIdentifier: String = "com.test.app",
        displayName: String = "Test App"
    ) -> MockSimulatorApp {
        return MockSimulatorApp(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName
        )
    }
    
    // MARK: - AppChange Test Data
    
    static func createMockAppChange(
        app: any SimulatorApp = createMockApp(),
        device: Device = createMockDevice(),
        changeType: ChangeType = .installed,
        timestamp: Date = Date()
    ) -> AppChange {
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
