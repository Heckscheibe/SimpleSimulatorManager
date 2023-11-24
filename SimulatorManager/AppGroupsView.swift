//
//  AppGroupsView.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 24.11.23.
//

import Foundation
import SwiftUI

struct AppGroupsView: View {
    @ObservedObject var viewModel: DeviceViewModel

    var body: some View {
        if !viewModel.device.appGroups.isEmpty {
            Text("AppGroups")
        }
        ForEach(viewModel.device.appGroups) { appGroup in
            Button {
                viewModel.didSelect(appGroup: appGroup)
            } label: {
                Text("Group \(appGroup.name)")
            }
        }
    }
}
