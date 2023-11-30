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
    @Published var visiblePlatforms: Set<SimulatorPlatform>
    
    init() {
        self.showAppleTVText = settings.showAppleTV ? "Hide Apple TV" : "Show Apple TV"
        self.showVisionText = settings.showVisionPro ? "Hide Vision OS" : "Hide Vision OS"
        self.showIPadText = settings.showIPad ? "Hide iPadOS" : "Show iPadOS"
        self.showIPhoneText = settings.showIPhone ? "Hide iOS" : "Show iOS"
        self.showWatchText = settings.showWatch ? "Hide WatchOS" : "Show WatchOS"
        
        self.visiblePlatforms = Set([
            settings.showAppleTV ? SimulatorPlatform.appleTV : nil,
            settings.showVisionPro ? .visionPro : nil,
            settings.showIPad ? .iPad : nil,
            settings.showIPhone ? .iPhone : nil,
            settings.showWatch ? .watch : nil
        ].compactMap { $0 })
    }
    
    func toggleAppleTVVisibility() {
        settings.showAppleTV.toggle()
        showAppleTVText = settings.showAppleTV ? "Hide Apple TV" : "Show Apple TV"
        updateVisiblePlatforms()
    }
    
    func toggleVisionProVisibility() {
        settings.showVisionPro.toggle()
        showVisionText = settings.showVisionPro ? "Hide Vision OS" : "Hide Vision OS"
        updateVisiblePlatforms()
    }
    
    func toggleIPadVisibility() {
        settings.showIPad.toggle()
        showIPadText = settings.showIPad ? "Hide iPadOS" : "Show iPadOS"
        updateVisiblePlatforms()
    }
    
    func toggleIPhoneVisibility() {
        settings.showIPhone.toggle()
        showIPhoneText = settings.showIPhone ? "Hide iOS" : "Show iOS"
        updateVisiblePlatforms()
    }
    
    func toggleWatchVisibility() {
        settings.showWatch.toggle()
        showWatchText = settings.showWatch ? "Hide WatchOS" : "Show WatchOS"
        updateVisiblePlatforms()
    }
}

private extension SettingsViewModel {
    func updateVisiblePlatforms() {
        visiblePlatforms = Set([
            settings.showAppleTV ? SimulatorPlatform.appleTV : nil,
            settings.showVisionPro ? .visionPro : nil,
            settings.showIPad ? .iPad : nil,
            settings.showIPhone ? .iPhone : nil,
            settings.showWatch ? .watch : nil
        ].compactMap { $0 })
    }
}
