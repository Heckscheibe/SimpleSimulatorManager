//
//  SimulatorManagerApp.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 11.10.23.
//

import SwiftUI
import os

@main struct SimulatorManagerApp: App {
    @StateObject private var deviceManager: DeviceManager
    @StateObject private var viewModel: SimulatorManagerViewModel
    @StateObject private var settings: Settings
        
    init() {
        let deviceManager = DeviceManager()
        let viewModel = SimulatorManagerViewModel(deviceManager: deviceManager)
        let settings = Settings()
        
        self._deviceManager = StateObject(wrappedValue: deviceManager)
        self._viewModel = StateObject(wrappedValue: viewModel)
        self._settings = StateObject(wrappedValue: settings)
    }
    
    var body: some Scene {
        MenuBarExtra("SimulatorManager", systemImage: "iphone.gen3") {
            RecentAppsView(viewModel: viewModel, settings: settings)
            Divider()
            DeviceTypeView(viewModel: viewModel, settings: settings)
            Divider()
            SettingsView(viewModel: SettingsViewModel(settings: settings, simulatorManagerViewModel: viewModel))
            Divider()
            ResetSimulatorsView(viewModel: ResetSimulatorsViewModel())
            Divider()
            GitHubView()
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }.keyboardShortcut("q")
        }
    }
}
