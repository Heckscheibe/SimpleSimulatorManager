//
//  DeviceTypeView.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 30.11.23.
//

import Foundation
import SwiftUI

struct DeviceTypeView: View {
    @ObservedObject var viewModel: SimulatorManagerViewModel
    @ObservedObject var settings: SettingsViewModel
    
    var body: some View {
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
                            AppsView(viewModel: DeviceViewModel(device: device))
                            Divider()
                            AppGroupsView(viewModel: DeviceViewModel(device: device))
                            Divider()
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
}
