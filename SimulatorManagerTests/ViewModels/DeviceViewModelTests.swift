//
//  DeviceViewModelTests.swift
//  SimulatorManagerTests
//
//  Created by Copilot on 18.03.26.
//

import Foundation
import Testing
@testable import SimulatorManager

@Suite("DeviceViewModel Tests")
struct DeviceViewModelTests {
    @Test("Erasing a device refreshes it through the device manager")
    @MainActor
    func eraseRefreshesDevice() async throws {
        let deviceManager = MockDeviceManager()
        let device = TestDataHelpers.createOfflineDevice(udid: "device-1")
        let refreshedDevice = TestDataHelpers.createOfflineDevice(udid: "device-1")
        let service = MockSimulatorDeviceActionService()
        let viewModel = DeviceViewModel(
            device: device,
            deviceManager: deviceManager,
            simulatorResetService: service
        )

        deviceManager.setMockDevices([refreshedDevice])

        viewModel.eraseDevice()
        try await Task.sleep(nanoseconds: 200_000_000)

        let shutDownDeviceUdid = await service.shutDownDeviceUdid
        let erasedDeviceUdid = await service.erasedDeviceUdid

        #expect(shutDownDeviceUdid == "device-1")
        #expect(erasedDeviceUdid == "device-1")
        #expect(deviceManager.refreshDeviceCalled)
        #expect(viewModel.device.state == .off)
        #expect(viewModel.actionErrorMessage == nil)
        #expect(!viewModel.isPerformingAction)
    }

    @Test("Erasing a running device shuts it down before erasing")
    @MainActor
    func eraseShutsDownRunningDevice() async throws {
        let deviceManager = MockDeviceManager()
        let service = MockSimulatorDeviceActionService()
        let refreshedDevice = TestDataHelpers.createOfflineDevice(udid: "test-device-uuid")
        let viewModel = DeviceViewModel(
            device: TestDataHelpers.createMockDevice(state: .running),
            deviceManager: deviceManager,
            simulatorResetService: service
        )

        deviceManager.setMockDevices([refreshedDevice])

        viewModel.eraseDevice()
        try await Task.sleep(nanoseconds: 200_000_000)

        let shutDownDeviceUdid = await service.shutDownDeviceUdid
        let erasedDeviceUdid = await service.erasedDeviceUdid

        #expect(shutDownDeviceUdid == "test-device-uuid")
        #expect(erasedDeviceUdid == "test-device-uuid")
        #expect(deviceManager.refreshDeviceCalled)
        #expect(viewModel.actionErrorMessage == nil)
        #expect(!viewModel.isPerformingAction)
    }

    @Test("Service failures are surfaced on the view model")
    @MainActor
    func actionFailure() async throws {
        struct TestFailure: LocalizedError {
            var errorDescription: String? {
                "simctl failed"
            }
        }

        let service = MockSimulatorDeviceActionService()
        await service.setError(TestFailure())

        let viewModel = DeviceViewModel(
            device: TestDataHelpers.createOfflineDevice(),
            deviceManager: MockDeviceManager(),
            simulatorResetService: service
        )

        viewModel.eraseDevice()
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(viewModel.actionErrorMessage == "simctl failed")
        #expect(!viewModel.isPerformingAction)
    }
}
