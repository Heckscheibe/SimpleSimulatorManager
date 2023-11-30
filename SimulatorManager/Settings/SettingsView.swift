//
//  SettingsView.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 24.11.23.
//

import Foundation
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel = SettingsViewModel()
    
    var body: some View {
        Button(action: {
            viewModel.toggleAppleTVVisibility()
        }, label: {
            Text(viewModel.showAppleTVButtonText)
        })
        
        Button(action: {
            viewModel.toggleIOSVisibility()
        }, label: {
            Text(viewModel.showIOSText)
        })
        
        Button(action: {
            viewModel.toggleIPadOSVisibility()
        }, label: {
            Text(viewModel.showIPadOSText)
        })
        
        Button(action: {
            viewModel.toggleVisionOSVisibility()
        }, label: {
            Text(viewModel.showVisionOSText)
        })
        
        Button(action: {
            viewModel.toggleWatchOSVisibility()
        }, label: {
            Text(viewModel.showWatchOSText)
        })
    }
}
