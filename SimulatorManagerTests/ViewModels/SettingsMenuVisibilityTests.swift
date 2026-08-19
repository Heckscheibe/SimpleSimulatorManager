import Foundation
import Testing
@testable import SimulatorManager

/// The settings section of the menu bar popup shows a per-platform toggle only when a simulator of
/// that platform exists. Those flags read `SimulatorManagerViewModel.deviceTypes`, which is derived
/// from the device manager's devices publisher — the same path `resetAndLoadDevices` republishes —
/// so a reload that stopped feeding it would silently empty the settings menu.
@Suite("Settings menu visibility")
struct SettingsMenuVisibilityTests {
    private enum Fixture {
        static let iPhoneUDID = "11111111-1111-1111-1111-111111111111"
        static let watchUDID = "22222222-2222-2222-2222-222222222222"
    }

    @Test("Only platforms with simulators present get a settings toggle")
    @MainActor
    func togglesReflectAvailablePlatforms() async throws {
        let fixture = try DeviceFixtureDirectory()
        defer { fixture.remove() }

        try fixture.writeDevice(
            udid: Fixture.iPhoneUDID,
            name: "iPhone 16 Pro",
            deviceTypeIdentifier: DeviceFixtureDirectory.DeviceTypeIdentifier.iPhone
        )
        try fixture.writeDevice(
            udid: Fixture.watchUDID,
            name: "Apple Watch Series 11 (46mm)",
            deviceTypeIdentifier: DeviceFixtureDirectory.DeviceTypeIdentifier.watch
        )

        let viewModel = try await makeSettingsViewModel(for: fixture)

        #expect(viewModel.hasIPhoneDevices)
        #expect(viewModel.hasWatchDevices)
        #expect(!viewModel.hasIPadDevices)
        #expect(!viewModel.hasAppleTVDevices)
        #expect(!viewModel.hasVisionProDevices)
    }

    @Test("Removing a simulator drops its toggle after a reload")
    @MainActor
    func togglesFollowAReload() async throws {
        let fixture = try DeviceFixtureDirectory()
        defer { fixture.remove() }

        try fixture.writeDevice(
            udid: Fixture.iPhoneUDID,
            name: "iPhone 16 Pro",
            deviceTypeIdentifier: DeviceFixtureDirectory.DeviceTypeIdentifier.iPhone
        )
        try fixture.writeDevice(
            udid: Fixture.watchUDID,
            name: "Apple Watch Series 11 (46mm)",
            deviceTypeIdentifier: DeviceFixtureDirectory.DeviceTypeIdentifier.watch
        )

        let deviceManager = DeviceManager(devicesDirectoryURL: fixture.url)
        let viewModel = try await makeSettingsViewModel(for: fixture, deviceManager: deviceManager)

        #expect(viewModel.hasWatchDevices)

        // Stand in for a cleanup deletion: the simulator disappears from disk and the app reloads.
        fixture.removeDevice(udid: Fixture.watchUDID)
        await deviceManager.resetAndLoadDevices()
        await drainMainQueue()

        #expect(!viewModel.hasWatchDevices)
        #expect(viewModel.hasIPhoneDevices)
    }

    // MARK: - Helpers

    /// Note: `Settings` reads the shared "SimulatorManager" defaults suite, so these cases assert
    /// only on the device-driven visibility flags, never on the toggle titles.
    @MainActor
    private func makeSettingsViewModel(
        for fixture: DeviceFixtureDirectory,
        deviceManager: DeviceManager? = nil
    ) async throws -> SettingsViewModel {
        let deviceManager = deviceManager ?? DeviceManager(devicesDirectoryURL: fixture.url)
        let simulatorManagerViewModel = SimulatorManagerViewModel(
            deviceManager: deviceManager,
            simulatorResetService: MockSimulatorDeviceActionService(),
            deviceAppMonitoringService: MockDeviceAppMonitoringService()
        )

        await drainMainQueue()

        return SettingsViewModel(settings: Settings(), simulatorManagerViewModel: simulatorManagerViewModel)
    }

    /// The view model binds with `.receive(on: DispatchQueue.main)`, so values land a main-queue
    /// turn later. Draining turns keeps this deterministic instead of sleeping for a guessed delay.
    private func drainMainQueue(turns: Int = 3) async {
        for _ in 0 ..< turns {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async {
                    continuation.resume()
                }
            }
        }
    }
}
