//
//  SimulatorManagerApp.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 11.10.23.
//

import SwiftUI
import os

@main struct SimulatorManagerApp: App {
    @ObservedObject private var viewModel = SimulatorManagerViewModel()
    @ObservedObject private var settingsViewModel = SettingsViewModel()
    
    var body: some Scene {
        MenuBarExtra("SimulatorManager", systemImage: "iphone.gen3") {
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
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }.keyboardShortcut("q")
        }
    }
}
