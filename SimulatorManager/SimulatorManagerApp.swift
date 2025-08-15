//
//  SimulatorManagerApp.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 11.10.23.
//

import SwiftUI
import os

@main struct SimulatorManagerApp: App {
    @StateObject private var settingsViewModel = SettingsViewModel()
    @StateObject private var deviceManager: DeviceManager
    @StateObject private var viewModel: SimulatorManagerViewModel
        
    init() {
        let deviceManager = DeviceManager()
        let viewModel = SimulatorManagerViewModel(deviceManager: deviceManager)
        
        self._deviceManager = StateObject(wrappedValue: deviceManager)
        self._viewModel = StateObject(wrappedValue: viewModel)
    }
    
    var body: some Scene {
        MenuBarExtra("SimulatorManager", systemImage: "iphone.gen3") {
            VStack {
                RecentAppsView(viewModel: viewModel, settings: settingsViewModel)
                Divider()
                DeviceTypeView(viewModel: viewModel, settings: settingsViewModel)
                Divider()
                SettingsView(viewModel: settingsViewModel)
                Divider()
                GitHubView()
                Divider()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }.keyboardShortcut("q")
            }
        }
    }
}
