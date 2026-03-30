//
//  SimulatorManagerApp.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 11.10.23.
//

import SwiftUI
import os

@main
struct SimulatorManagerApp: App {
    @StateObject private var deviceManager: DeviceManager
    @State private var viewModel: SimulatorManagerViewModel
    @State private var cleanupSimulatorsViewModel: CleanupSimulatorsViewModel
    @State private var resetSimulatorsViewModel: ResetSimulatorsViewModel
    @State private var settingsViewModel: SettingsViewModel
    @StateObject private var settings: Settings
    
    private let simulatorResetService: SimulatorResetServing
    private let simulatorCleanupService: SimulatorCleanupServing
        
    init() {
        let deviceManager = DeviceManager()
        let simulatorResetService: SimulatorResetServing = SimulatorResetService()
        let simulatorCleanupService: SimulatorCleanupServing = SimulatorCleanupService()
        let viewModel = SimulatorManagerViewModel(deviceManager: deviceManager,
                                                  simulatorResetService: simulatorResetService)
        let cleanupSimulatorsViewModel = CleanupSimulatorsViewModel(cleanupService: simulatorCleanupService,
                                                                    deviceManager: deviceManager)
        let resetSimulatorsViewModel = ResetSimulatorsViewModel(deviceManager: deviceManager,
                                                                simulatorResetService: simulatorResetService)
        let settings = Settings()
        
        self.simulatorResetService = simulatorResetService
        self.simulatorCleanupService = simulatorCleanupService
        self._deviceManager = StateObject(wrappedValue: deviceManager)
        self._viewModel = State(initialValue: viewModel)
        self._cleanupSimulatorsViewModel = State(initialValue: cleanupSimulatorsViewModel)
        self._resetSimulatorsViewModel = State(initialValue: resetSimulatorsViewModel)
        self._settingsViewModel = State(initialValue: SettingsViewModel(settings: settings,
                                                                        simulatorManagerViewModel: viewModel))
        self._settings = StateObject(wrappedValue: settings)
    }
    
    var body: some Scene {
        MenuBarExtra("SimulatorManager", systemImage: "iphone.gen3") {
            RecentAppsView(viewModel: viewModel, settings: settings)
            Divider()
            DeviceTypeView(viewModel: viewModel, settings: settings)
            Divider()
            SettingsView(viewModel: settingsViewModel, settings: settings)
            Divider()
            CleanupSimulatorsView(viewModel: cleanupSimulatorsViewModel)
            Divider()
            ResetSimulatorsView(viewModel: resetSimulatorsViewModel)
            Divider()
            GitHubView()
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }.keyboardShortcut("q")
        }
    }
}
