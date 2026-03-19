//
//  SettingsViewModel.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 24.11.23.
//

import Foundation
import Combine

@MainActor
class SettingsViewModel: ObservableObject {
    private var settings: Settings
    private var simulatorManagerViewModel: SimulatorManagerViewModel
    private var cancellables = Set<AnyCancellable>()
    
    /// Constants for platform names
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
    
    // Published properties to control button visibility
    @Published var hasAppleTVDevices = false
    @Published var hasVisionProDevices = false
    @Published var hasIPadDevices = false
    @Published var hasIPhoneDevices = false
    @Published var hasWatchDevices = false
    
    init(settings: Settings, simulatorManagerViewModel: SimulatorManagerViewModel) {
        self.settings = settings
        self.simulatorManagerViewModel = simulatorManagerViewModel
        self.showAppleTVText = Self.toggleText(for: PlatformText.appleTV, isVisible: settings.showTVOS)
        self.showVisionText = Self.toggleText(for: PlatformText.visionOS, isVisible: settings.showVisionOS)
        self.showIPadText = Self.toggleText(for: PlatformText.iPadOS, isVisible: settings.showIPadOS)
        self.showIPhoneText = Self.toggleText(for: PlatformText.iOS, isVisible: settings.showIOS)
        self.showWatchText = Self.toggleText(for: PlatformText.watchOS, isVisible: settings.showWatchOS)
        self.showRecentAppsText = Self.toggleText(for: PlatformText.recentApps, isVisible: settings.showRecentApps)
        
        bindDevices()
    }
    
    func toggleTVOSVisibility() {
        settings.showTVOS.toggle()
        showAppleTVText = Self.toggleText(for: PlatformText.appleTV, isVisible: settings.showTVOS)
    }
    
    func toggleVisionOSVisibility() {
        settings.showVisionOS.toggle()
        showVisionText = Self.toggleText(for: PlatformText.visionOS, isVisible: settings.showVisionOS)
    }
    
    func toggleIPadOSVisibility() {
        settings.showIPadOS.toggle()
        showIPadText = Self.toggleText(for: PlatformText.iPadOS, isVisible: settings.showIPadOS)
    }
    
    func toggleIOSVisibility() {
        settings.showIOS.toggle()
        showIPhoneText = Self.toggleText(for: PlatformText.iOS, isVisible: settings.showIOS)
    }
    
    func toggleWatchOSVisibility() {
        settings.showWatchOS.toggle()
        showWatchText = Self.toggleText(for: PlatformText.watchOS, isVisible: settings.showWatchOS)
    }
    
    func toggleRecentAppsVisibility() {
        settings.showRecentApps.toggle()
        showRecentAppsText = Self.toggleText(for: PlatformText.recentApps, isVisible: settings.showRecentApps)
    }
}

private extension SettingsViewModel {
    struct DeviceAvailability {
        let hasAppleTV: Bool
        let hasVisionPro: Bool
        let hasIPad: Bool
        let hasIPhone: Bool
        let hasWatch: Bool
    }
    
    /// Helper method to generate toggle text
    static func toggleText(for platform: String, isVisible: Bool) -> String {
        return isVisible ? "Hide \(platform)" : "Show \(platform)"
    }
    
    func bindDevices() {
        simulatorManagerViewModel.$deviceTypes
            .removeDuplicates()
            .map { deviceTypes in
                let platforms = Set(deviceTypes.map { $0.simulatorPlatform })
                return DeviceAvailability(
                    hasAppleTV: platforms.contains(.appleTV),
                    hasVisionPro: platforms.contains(.visionPro),
                    hasIPad: platforms.contains(.iPad),
                    hasIPhone: platforms.contains(.iPhone) || platforms.contains(.iPodTouch),
                    hasWatch: platforms.contains(.watch)
                )
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (availability: DeviceAvailability) in
                self?.hasAppleTVDevices = availability.hasAppleTV
                self?.hasVisionProDevices = availability.hasVisionPro
                self?.hasIPadDevices = availability.hasIPad
                self?.hasIPhoneDevices = availability.hasIPhone
                self?.hasWatchDevices = availability.hasWatch
            }
            .store(in: &cancellables)
    }
}
