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
        Text(viewModel.stateDescription)

        if let actionErrorMessage = viewModel.actionErrorMessage {
            Text(actionErrorMessage)
                .font(.system(size: 12))
        }

        if viewModel.hasAppsInstalled {
            Menu(viewModel.osVersion) {
                Divider()
                AppsView(viewModel: viewModel)
                Divider()
                AppGroupsView(viewModel: viewModel)
                Divider()
            }
        } else {
            Text(viewModel.osVersion)
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
        
        if viewModel.isPerformingAction {
            Text(viewModel.currentActionTitle)
        } else {
            Button(role: .destructive) {
                viewModel.eraseDevice()
            } label: {
                Text("Erase Simulator")
            }
        }
        
        Divider()
    }
}
