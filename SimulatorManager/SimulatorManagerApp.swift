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
    @State private var resetSimulatorsViewModel: ResetSimulatorsViewModel
    @State private var settingsViewModel: SettingsViewModel
    @StateObject private var settings: Settings
    
    private let simulatorResetService: SimulatorResetServing
        
    init() {
        let deviceManager = DeviceManager()
        let simulatorResetService: SimulatorResetServing = SimulatorResetService()
        let viewModel = SimulatorManagerViewModel(deviceManager: deviceManager,
                                                  simulatorResetService: simulatorResetService)
        let resetSimulatorsViewModel = ResetSimulatorsViewModel(deviceManager: deviceManager,
                                                                simulatorResetService: simulatorResetService)
        let settings = Settings()
        
        self.simulatorResetService = simulatorResetService
        self._deviceManager = StateObject(wrappedValue: deviceManager)
        self._viewModel = State(initialValue: viewModel)
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
