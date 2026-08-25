//
//  AppGroupsView.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 24.11.23.
//

import Foundation
import SwiftUI

struct AppGroupsView: View {
    let viewModel: DeviceViewModel

    var body: some View {
        if !viewModel.appGroups.isEmpty {
            Text("AppGroups")
        }
        ForEach(viewModel.device.appGroups) { appGroup in
            Menu("Group \(appGroup.name)") {
                ForEach(AppGroupShortcut.available(for: appGroup)) { shortcut in
                    Button {
                        viewModel.didSelectFolder(shortcut, for: appGroup)
                    } label: {
                        Text(shortcut.title)
                    }
                }

                Divider()

                Menu("Copy Path") {
                    ForEach(AppGroupShortcut.available(for: appGroup)) { shortcut in
                        Button {
                            viewModel.didSelectCopyPath(of: shortcut, for: appGroup)
                        } label: {
                            Text(shortcut.title)
                        }
                    }
                }

                if appGroup.hasUserDefaults {
                    Button {
                        viewModel.didSelectCopyUserDefaultsJSON(for: appGroup)
                    } label: {
                        Text("Copy UserDefaults as JSON")
                    }
                }
            }
        }
    }
}
