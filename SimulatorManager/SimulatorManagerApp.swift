//
//  SimulatorManagerApp.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 11.10.23.
//

import SwiftUI
import os

@main struct SimulatorManagerApp: App {
    let viewModel = SimulatorManagerViewModel()
    
    var body: some Scene {
        MenuBarExtra("SimulatorManager", systemImage: "iphone.gen3") {
            deviceTypeMenu
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }.keyboardShortcut("q")
        }
    }
    
    var deviceTypeMenu: some View {
        ForEach(viewModel.deviceTypes) { deviceType in
            Menu(deviceType.name) {
                ForEach(viewModel.devices.filter { $0.name == deviceType.name }) { device in
                    if device.hasAppsInstalled {
                        Menu(device.osVersion) {
                            Button {
                                viewModel.didSelectSimulatorFolder(for: device)
                            } label: {
                                Text("Simulator Folder")
                            }
                            Button {
                                viewModel.didSelectAppsFolder(for: device)
                            } label: {
                                Text("Application Folder")
                            }
                            Divider()
                            appView(for: device)
                            Divider()
                            appGroupsView(for: device)
                        }
                    } else {
                        Text(device.osVersion)
                        Text("No apps installed")
                            .font(.system(size: 12))
                    }
                }
            }
        }
    }
    
    func appView(for device: Device) -> some View {
        ForEach(device.apps, id: \.id) { app in
            Menu(app.displayName) {
                Button {
                    viewModel.didSelectAppDocumentFolder(for: app)
                } label: {
                    HStack {
                        Text("Documents Folder")
                    }
                }
                Button {
                    viewModel.didSelectAppPackageFolder(for: app)
                } label: {
                    HStack {
                        Text("App Package")
                    }
                }
            }
        }
    }
    
    func appGroupsView(for device: Device) -> some View {
        ForEach(device.appGroups) { appGroup in
            Button {
                viewModel.didSelect(appGroup: appGroup)
            } label: {
                Text("Group \(appGroup.name)")
            }
        }
    }
}
