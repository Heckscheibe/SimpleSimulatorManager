//
//  RecentAppsView.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 11.07.25.
//

import SwiftUI

struct RecentAppsView: View {
    let viewModel: SimulatorManagerViewModel
    @ObservedObject var settings: Settings
    
    var body: some View {
        if settings.showRecentApps {
            if !viewModel.recentInstalledApps.isEmpty {
                Text("Recent Apps")
                ForEach(viewModel.recentInstalledApps, id: \.id) { appChange in
                    Menu {
                        AppShortcutMenuItems(app: appChange.app, actions: viewModel)
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
