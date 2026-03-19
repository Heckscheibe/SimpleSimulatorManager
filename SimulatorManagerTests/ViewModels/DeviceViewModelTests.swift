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
    @Test("Erase action is available regardless of simulator state")
    @MainActor
    func eraseAvailability() {
        let device = TestDataHelpers.createMockDevice(state: .running)
        let viewModel = DeviceViewModel(
            device: device,
            deviceManager: MockDeviceManager(),
            simulatorResetService: MockSimulatorDeviceActionService()
        )

        #expect(viewModel.canEraseDevice)
    }

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
        #expect(deviceManager.updateSpecificDeviceCalled)
        #expect(viewModel.device.state == .off)
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
