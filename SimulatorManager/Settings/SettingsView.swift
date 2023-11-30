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
            Text(viewModel.showAppleTVText)
        })
        
        Button(action: {
            viewModel.toggleIPhoneVisibility()
        }, label: {
            Text(viewModel.showIPhoneText)
        })
        
        Button(action: {
            viewModel.toggleIPadVisibility()
        }, label: {
            Text(viewModel.showIPadText)
        })
        
        Button(action: {
            viewModel.toggleVisionProVisibility()
        }, label: {
            Text(viewModel.showVisionText)
        })
        
        Button(action: {
            viewModel.toggleWatchVisibility()
        }, label: {
            Text(viewModel.showWatchText)
        })
    }
}
