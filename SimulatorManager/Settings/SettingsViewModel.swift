//
//  SettingsViewModel.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 24.11.23.
//

import Foundation

class SettingsViewModel: ObservableObject {
    private var settings = Settings()
    
    var showAppleTVButtonText: String {
        settings.showAppleTV ? "Hide AppleTV" : "Show AppleTV"
    }

    var showVisionOSButtonText: String {
        settings.showVisionOS ? "Hide VisionOS" : "Show VisionOS"
    }

    var showIPadOSText: String {
        settings.showIPadOS ? "Hide iPadOS" : "Show iPadOS"
    }

    var showIOSText: String
    
    init() {
        self.showIOSText = settings.showIOS ? "Hide iOS" : "Show iOS"
    }
    
    func toggleAppleTVVisibility() {
        settings.showAppleTV.toggle()
    }
    
    func toggleVisionOSVisibility() {
        settings.showVisionOS.toggle()
    }
    
    func toggleIPadOSVisibility() {
        settings.showIPadOS.toggle()
    }
    
    func toggleIOSVisibility() {
        settings.showIOS = !settings.showIOS
        
        showIOSText = settings.showIOS ? "Hide iOS" : "Show iOS"
    }
}
