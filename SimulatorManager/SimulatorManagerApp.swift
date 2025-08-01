//
//  SimulatorManagerApp.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 11.10.23.
//

import SwiftUI
import os

@main struct SimulatorManagerApp: App {
    @StateObject private var deviceManager = DeviceManager()
    @StateObject private var settingsViewModel = SettingsViewModel()
    @StateObject private var viewModel: SimulatorManagerViewModel
    
    init() {
        let deviceManager = DeviceManager()
        let viewModel = SimulatorManagerViewModel(deviceManager: deviceManager)
        
        self._deviceManager = StateObject(wrappedValue: deviceManager)
        self._viewModel = StateObject(wrappedValue: viewModel)
    }
    
    var body: some Scene {
        MenuBarExtra("SimulatorManager", systemImage: "iphone.gen3") {
            RecentAppsView(viewModel: viewModel, settings: settingsViewModel)
            Divider()
            DeviceTypeView(viewModel: viewModel, settings: settingsViewModel)
            Divider()
            SettingsView(viewModel: settingsViewModel)
            Divider()
            Button("GitHub Project") {
                guard let url = URL(string: "https://github.com/Heckscheibe/SimpleSimulatorManager") else {
                    return
                }
                NSWorkspace.shared.open(url)
            }
            if let version = Bundle.main.infoDictionary!["CFBundleShortVersionString"] as? String {
                Divider()
                Text("Version \(version)")
                    .font(.system(size: 12))
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }.keyboardShortcut("q")
        }
    }
}
