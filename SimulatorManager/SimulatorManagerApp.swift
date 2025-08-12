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
    @StateObject private var githubService = GithubService()
        
    init() {
        let deviceManager = DeviceManager()
        let viewModel = SimulatorManagerViewModel(deviceManager: deviceManager)
        
        self._deviceManager = StateObject(wrappedValue: deviceManager)
        self._viewModel = StateObject(wrappedValue: viewModel)
        
        githubService.startPeriodicUpdateCheck()
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
                githubService.openGithubProject()
            }
            if let version = Bundle.main.infoDictionary!["CFBundleShortVersionString"] as? String {
                Divider()
                if githubService.isUpdateAvailable {
                    Button {
                        githubService.openLatestRelease()
                    } label: {
                        Text("! Update Available !")
                        Text("Version \(version)")
                    }
                } else {
                    Text("Version \(version)")
                }
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }.keyboardShortcut("q")
        }
    }
}
