//
//  SettingsView.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 24.11.23.
//

import Foundation
import SwiftUI

struct SettingsView: View {
    let viewModel = SettingsViewModel()
    
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
            Text(viewModel.showVisionOSButtonText)
        })
    }
}
