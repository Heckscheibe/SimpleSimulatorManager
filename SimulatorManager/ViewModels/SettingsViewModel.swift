//
//  SettingsViewModel.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 24.11.23.
//

import Foundation
import Observation

@MainActor
@Observable
class SettingsViewModel {
    @ObservationIgnored private let settings: Settings
    @ObservationIgnored private let simulatorManagerViewModel: SimulatorManagerViewModel
    
    /// Constants for platform names
    private enum PlatformText {
        static let appleTV = "Apple TV"
        static let visionOS = "visionOS"
        static let iPadOS = "iPadOS"
        static let iOS = "iOS"
        static let watchOS = "watchOS"
        static let recentApps = "Recent Apps"
    }
    
    init(settings: Settings, simulatorManagerViewModel: SimulatorManagerViewModel) {
        self.settings = settings
        self.simulatorManagerViewModel = simulatorManagerViewModel
    }

    var showAppleTVText: String {
        Self.toggleText(for: PlatformText.appleTV, isVisible: settings.showTVOS)
    }

    var showVisionText: String {
        Self.toggleText(for: PlatformText.visionOS, isVisible: settings.showVisionOS)
    }

    var showIPadText: String {
        Self.toggleText(for: PlatformText.iPadOS, isVisible: settings.showIPadOS)
    }

    var showIPhoneText: String {
        Self.toggleText(for: PlatformText.iOS, isVisible: settings.showIOS)
    }

    var showWatchText: String {
        Self.toggleText(for: PlatformText.watchOS, isVisible: settings.showWatchOS)
    }

    var showRecentAppsText: String {
        Self.toggleText(for: PlatformText.recentApps, isVisible: settings.showRecentApps)
    }

    var hasAppleTVDevices: Bool {
        availablePlatforms.contains(.appleTV)
    }

    var hasVisionProDevices: Bool {
        availablePlatforms.contains(.visionPro)
    }

    var hasIPadDevices: Bool {
        availablePlatforms.contains(.iPad)
    }

    var hasIPhoneDevices: Bool {
        availablePlatforms.contains(.iPhone) || availablePlatforms.contains(.iPodTouch)
    }

    var hasWatchDevices: Bool {
        availablePlatforms.contains(.watch)
    }
    
    func toggleTVOSVisibility() {
        settings.showTVOS.toggle()
    }
    
    func toggleVisionOSVisibility() {
        settings.showVisionOS.toggle()
    }
    
    func toggleIPadOSVisibility() {
        settings.showIPadOS.toggle()
    }
    
    func toggleIOSVisibility() {
        settings.showIOS.toggle()
    }
    
    func toggleWatchOSVisibility() {
        settings.showWatchOS.toggle()
    }
    
    func toggleRecentAppsVisibility() {
        settings.showRecentApps.toggle()
    }
}

private extension SettingsViewModel {
    /// Helper method to generate toggle text
    static func toggleText(for platform: String, isVisible: Bool) -> String {
        return isVisible ? "Hide \(platform)" : "Show \(platform)"
    }

    var availablePlatforms: Set<SimulatorPlatform> {
        Set(simulatorManagerViewModel.deviceTypes.map(\.simulatorPlatform))
    }
}
