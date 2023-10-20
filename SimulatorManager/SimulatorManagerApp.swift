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
                            ForEach(device.apps) { app in
                                Button(action: {
                                    viewModel.didSelect(app: app)
                                }, label: {
                                    Text(app.displayName)
                                })
                            }
                        }
                    } else {
                        HStack(alignment: .center,
                               spacing: 10,
                               content: {
                                   Text(device.osVersion)
                                   Text("No apps installed")
                                       .font(.system(size: 12))
                               })
                    }
                }
            }
        }
    }
}
