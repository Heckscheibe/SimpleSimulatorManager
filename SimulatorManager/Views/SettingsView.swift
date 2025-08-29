//
//  SettingsView.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 24.11.23.
//

import Foundation
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    
    var body: some View {
        Button(action: {
            viewModel.toggleRecentAppsVisibility()
        }, label: {
            Text(viewModel.showRecentAppsText)
        })
        
        Divider()
        
        if viewModel.hasAppleTVDevices {
            Button(action: {
                viewModel.toggleTVOSVisibility()
            }, label: {
                Text(viewModel.showAppleTVText)
            })
        }
        
        if viewModel.hasVisionProDevices {
            Button(action: {
                viewModel.toggleVisionOSVisibility()
            }, label: {
                Text(viewModel.showVisionText)
            })
        }
        
        if viewModel.hasWatchDevices {
            Button(action: {
                viewModel.toggleWatchOSVisibility()
            }, label: {
                Text(viewModel.showWatchText)
            })
        }
        
        if viewModel.hasIPadDevices {
            Button(action: {
                viewModel.toggleIPadOSVisibility()
            }, label: {
                Text(viewModel.showIPadText)
            })
        }
        
        if viewModel.hasIPhoneDevices {
            Button(action: {
                viewModel.toggleIOSVisibility()
            }, label: {
                Text(viewModel.showIPhoneText)
            })
        }
    }
}
