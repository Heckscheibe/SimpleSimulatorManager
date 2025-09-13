//
//  DeviceView.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 13.09.25.
//

import Foundation
import SwiftUI

struct DeviceView: View {
    @ObservedObject var viewModel: DeviceViewModel
    
    var body: some View {
        if viewModel.device.hasAppsInstalled {
            Menu(viewModel.device.osVersion) {
                Divider()
                AppsView(viewModel: DeviceViewModel(device: viewModel.device))
                Divider()
                AppGroupsView(viewModel: DeviceViewModel(device: viewModel.device))
                Divider()
            }
        } else {
            Text(viewModel.device.osVersion)
            Text("No apps installed")
                .font(.system(size: 12))
        }
        Button {
            viewModel.didSelectSimulatorFolder(for: viewModel.device)
        } label: {
            Text("Simulator Folder")
        }
        
        if viewModel.hasAppsFolder {
            Button {
                viewModel.didSelectAppsFolder(for: viewModel.device)
            } label: {
                Text("App Folder")
            }
        }
        
        if viewModel.hasAppPackagesFolder {
            Button {
                viewModel.didSelectAppPackagesFolder(for: viewModel.device)
            } label: {
                Text("App Package Folder")
            }
        }
        
        Divider()
    }
}
