//
//  SettingsViewModel.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 24.11.23.
//

import Foundation

class SettingsViewModel: ObservableObject {
    private var settings = Settings()
    
    @Published var showAppleTVText: String
    @Published var showVisionText: String
    @Published var showIPadText: String
    @Published var showIPhoneText: String
    @Published var showWatchText: String
    
    init() {
        self.showAppleTVText = settings.showAppleTV ? "Hide Apple TV" : "Show Apple TV"
        self.showVisionText = settings.showVisionPro ? "Hide Vision OS" : "Hide Vision OS"
        self.showIPadText = settings.showIPad ? "Hide iPadOS" : "Show iPadOS"
        self.showIPhoneText = settings.showIPhone ? "Hide iOS" : "Show iOS"
        self.showWatchText = settings.showWatch ? "Hide WatchOS" : "Show WatchOS"
    }
    
    func toggleAppleTVVisibility() {
        settings.showAppleTV.toggle()
        showAppleTVText = settings.showAppleTV ? "Hide Apple TV" : "Show Apple TV"
    }
    
    func toggleVisionProVisibility() {
        settings.showVisionPro.toggle()
        showVisionText = settings.showVisionPro ? "Hide Vision OS" : "Hide Vision OS"
    }
    
    func toggleIPadVisibility() {
        settings.showIPad.toggle()
        showIPadText = settings.showIPad ? "Hide iPadOS" : "Show iPadOS"
    }
    
    func toggleIPhoneVisibility() {
        settings.showIPhone.toggle()
        showIPhoneText = settings.showIPhone ? "Hide iOS" : "Show iOS"
    }
    
    func toggleWatchVisibility() {
        settings.showWatch.toggle()
        showWatchText = settings.showWatch ? "Hide WatchOS" : "Show WatchOS"
    }
}
