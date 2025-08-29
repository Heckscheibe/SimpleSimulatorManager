//
//  RecentAppsView.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 11.07.25.
//

import SwiftUI
import Combine

struct RecentAppsView: View {
    @ObservedObject var viewModel: SimulatorManagerViewModel
    @ObservedObject var settings: Settings
    
    var body: some View {
        if Settings().showRecentApps {
            if !viewModel.recentInstalledApps.isEmpty {
                Text("Recent Apps")
                ForEach(viewModel.recentInstalledApps, id: \.id) { appChange in
                    Menu {
                        Button {
                            viewModel.didSelectAppDocumentFolder(for: appChange.app)
                        } label: {
                            Text("Documents Folder")
                        }
                        Button {
                            viewModel.didSelectAppPackageFolder(for: appChange.app)
                        } label: {
                            Text("App Package")
                        }
                        if appChange.app.hasUserDefaults {
                            Button {
                                viewModel.didSelectUserDefaultsFolder(for: appChange.app)
                            } label: {
                                Text("User Defaults")
                            }
                        }
                    } label: {
                        Text(appChange.app.displayName)
                        Text(appChange.device.name + " " + appChange.device.osVersion)
                    }
                }
            } else {
                Text("No Recent Apps")
                    .padding()
            }
        }
    }
}
