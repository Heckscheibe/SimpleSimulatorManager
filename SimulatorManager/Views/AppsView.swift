//
//  AppsView.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 24.11.23.
//

import Foundation
import SwiftUI

struct AppsView: View {
    @ObservedObject var viewModel: DeviceViewModel
    
    var body: some View {
        if !viewModel.device.hasAppsInstalled {
            Text("Apps")
        }
        ForEach(viewModel.device.apps, id: \.id) { app in
            Menu(app.displayName) {
                Button {
                    viewModel.didSelectAppDocumentFolder(for: app)
                } label: {
                    Text("Documents Folder")
                }
                Button {
                    viewModel.didSelectAppPackageFolder(for: app)
                } label: {
                    Text("App Package")
                }
                if app.hasUserDefaults {
                    Button {
                        viewModel.didSelectUserDefaultsFolder(for: app)
                    } label: {
                        Text("User Defaults")
                    }
                }
            }
        }
    }
}
