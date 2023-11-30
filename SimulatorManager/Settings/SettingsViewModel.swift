//
//  SettingsViewModel.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 24.11.23.
//

import Foundation

class SettingsViewModel: ObservableObject {
    private var settings = Settings()
    
    @Published var showAppleTVButtonText: String
    @Published var showVisionOSText: String
    @Published var showIPadOSText: String
    @Published var showIOSText: String
    @Published var showWatchOSText: String
    
    init() {
        self.showAppleTVButtonText = settings.showAppleTV ? "Hide Apple TV" : "Show Apple TV"
        self.showVisionOSText = settings.showVisionOS ? "Hide Vision OS" : "Hide Vision OS"
        self.showIPadOSText = settings.showIPadOS ? "Hide iPadOS" : "Show iPadOS"
        self.showIOSText = settings.showIOS ? "Hide iOS" : "Show iOS"
        self.showWatchOSText = settings.showWatchOS ? "Hide WatchOS" : "Show WatchOS"
    }
    
    func toggleAppleTVVisibility() {
        settings.showAppleTV.toggle()
        showAppleTVButtonText = settings.showAppleTV ? "Hide Apple TV" : "Show Apple TV"
    }
    
    func toggleVisionOSVisibility() {
        settings.showVisionOS.toggle()
        showVisionOSText = settings.showVisionOS ? "Hide Vision OS" : "Hide Vision OS"
    }
    
    func toggleIPadOSVisibility() {
        settings.showIPadOS.toggle()
        showIPadOSText = settings.showIPadOS ? "Hide iPadOS" : "Show iPadOS"
    }
    
    func toggleIOSVisibility() {
        settings.showIOS.toggle()
        showIOSText = settings.showIOS ? "Hide iOS" : "Show iOS"
    }
    
    func toggleWatchOSVisibility() {
        settings.showWatchOS.toggle()
        showWatchOSText = settings.showWatchOS ? "Hide WatchOS" : "Show WatchOS"
    }
}
