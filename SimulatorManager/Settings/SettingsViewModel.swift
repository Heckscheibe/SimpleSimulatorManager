//
//  SettingsViewModel.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 24.11.23.
//

import Foundation

class SettingsViewModel: ObservableObject {
    private var settings = Settings()
    
    // Constants for platform names
    private enum PlatformText {
        static let appleTV = "Apple TV"
        static let visionOS = "visionOS"
        static let iPadOS = "iPadOS"
        static let iOS = "iOS"
        static let watchOS = "watchOS"
        static let recentApps = "Recent Apps"
    }
    
    @Published var showAppleTVText: String
    @Published var showVisionText: String
    @Published var showIPadText: String
    @Published var showIPhoneText: String
    @Published var showWatchText: String
    @Published var showRecentAppsText: String
    @Published var visiblePlatforms = Set<SimulatorPlatform>()
    
    init() {
        self.showAppleTVText = Self.toggleText(for: PlatformText.appleTV, isVisible: settings.showAppleTV)
        self.showVisionText = Self.toggleText(for: PlatformText.visionOS, isVisible: settings.showVisionPro)
        self.showIPadText = Self.toggleText(for: PlatformText.iPadOS, isVisible: settings.showIPad)
        self.showIPhoneText = Self.toggleText(for: PlatformText.iOS, isVisible: settings.showIPhone)
        self.showWatchText = Self.toggleText(for: PlatformText.watchOS, isVisible: settings.showWatch)
        self.showRecentAppsText = Self.toggleText(for: PlatformText.recentApps, isVisible: settings.showRecentApps)
        
        updateVisiblePlatforms()
    }
    
    // Helper method to generate toggle text
    private static func toggleText(for platform: String, isVisible: Bool) -> String {
        return isVisible ? "Hide \(platform)" : "Show \(platform)"
    }
    
    func toggleAppleTVVisibility() {
        settings.showAppleTV.toggle()
        showAppleTVText = Self.toggleText(for: PlatformText.appleTV, isVisible: settings.showAppleTV)
        updateVisiblePlatforms()
    }
    
    func toggleVisionProVisibility() {
        settings.showVisionPro.toggle()
        showVisionText = Self.toggleText(for: PlatformText.visionOS, isVisible: settings.showVisionPro)
        updateVisiblePlatforms()
    }
    
    func toggleIPadVisibility() {
        settings.showIPad.toggle()
        showIPadText = Self.toggleText(for: PlatformText.iPadOS, isVisible: settings.showIPad)
        updateVisiblePlatforms()
    }
    
    func toggleIPhoneVisibility() {
        settings.showIPhone.toggle()
        showIPhoneText = Self.toggleText(for: PlatformText.iOS, isVisible: settings.showIPhone)
        updateVisiblePlatforms()
    }
    
    func toggleWatchVisibility() {
        settings.showWatch.toggle()
        showWatchText = Self.toggleText(for: PlatformText.watchOS, isVisible: settings.showWatch)
        updateVisiblePlatforms()
    }
    
    func toggleRecentAppsVisibility() {
        settings.showRecentApps.toggle()
        showRecentAppsText = Self.toggleText(for: PlatformText.recentApps, isVisible: settings.showRecentApps)
    }
}

private extension SettingsViewModel {
    func updateVisiblePlatforms() {
        visiblePlatforms = Set([
            settings.showAppleTV ? SimulatorPlatform.appleTV : nil,
            settings.showVisionPro ? .visionPro : nil,
            settings.showIPad ? .iPad : nil,
            settings.showIPhone ? .iPhone : nil,
            settings.showIPhone ? .iPodTouch : nil,
            settings.showWatch ? .watch : nil
        ].compactMap { $0 })
    }
}
