//
//  RecentAppsView.swift
//  SimulatorManager
//
//  Created by AI Assistant on 11.07.25.
//

import SwiftUI
import Combine

struct RecentAppsView: View {
    @ObservedObject var viewModel: SimulatorManagerViewModel
    @ObservedObject var settings: SettingsViewModel
    
    var body: some View {
        if Settings().showRecentApps {
            ForEach(viewModel.recentAppChanges, id: \.id) { appChange in
                Menu {
                    Button {
                        viewModel.didSelectAppDocumentFolder(for: appChange.app)
                    } label: {
                        Text("Documents Folder")
                    }
                    Button {
                        viewModel.didSelectAppPackageFolder(for: appChange.app)
                    } label: {
                        Text("App Package")
                    }
                    if appChange.app.hasUserDefaults {
                        Button {
                            viewModel.didSelectUserDefaultsFolder(for: appChange.app)
                        } label: {
                            Text("User Defaults")
                        }
                    }
                } label: {
                    Text(appChange.app.displayName)
                    Text(appChange.device.name + " " + appChange.device.osVersion)
                }
            }
        }
    }
}

struct RecentAppRow: View {
    let change: AppChange
    
    var body: some View {
        HStack(spacing: 12) {
            // App icon
            Image(systemName: change.app.iconName)
                .foregroundColor(.accentColor)
                .frame(width: 20, height: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                // App name and update type
                HStack {
                    Text(change.app.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
                
                // Bundle identifier and device info
                HStack {
                    Text(change.app.bundleIdentifier)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text(change.device.name)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.05))
        )
        .contextMenu {
            contextMenuItems
        }
    }
    
    @ViewBuilder private var contextMenuItems: some View {
        if let packageURL = change.app.appPackageURL {
            Button("Show in Finder") {
                NSWorkspace.shared.selectFile(packageURL.path, inFileViewerRootedAtPath: "")
            }
        }
        
        if let documentsURL = change.app.appDocumentsFolderURL {
            Button("Show Documents Folder") {
                NSWorkspace.shared.open(documentsURL)
            }
        }
        
        Button("Copy Bundle Identifier") {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(change.app.bundleIdentifier, forType: .string)
        }
        
        Divider()
        
        Button("Copy App Info") {
            let appInfo = """
            App: \(change.app.displayName)
            Bundle ID: \(change.app.bundleIdentifier)
            Device: \(change.device.name) (\(change.device.osVersion))
            Changed: \(change.timestamp.formatted())
            Type: \(change.changeType)
            """
            
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(appInfo, forType: .string)
        }
    }
}

// MARK: - Preview

#Preview("With Recent Apps") {
    let deviceManager = InlineDeviceManager()
    let deviceAppMonitoringService = DeviceAppMonitoringService(deviceManager: deviceManager)
    let viewModel = SimulatorManagerViewModel(deviceManager: deviceManager, deviceAppMonitoringService: deviceAppMonitoringService)
    let settings = SettingsViewModel()
    
    // Set up mock data
    let mockDevice = createInlineMockDevice()
    let mockApp = InlineMockApp()
    let appChange = AppChange(app: mockApp, device: mockDevice, changeType: .installed, timestamp: Date())
    
    return RecentAppsView(viewModel: viewModel, settings: settings)
        .frame(width: 320)
        .padding()
        .onAppear {
            viewModel.recentAppChanges = [appChange]
        }
}

#Preview("Empty State") {
    let deviceManager = InlineDeviceManager()
    let deviceAppMonitoringService = DeviceAppMonitoringService(deviceManager: deviceManager)
    let viewModel = SimulatorManagerViewModel(deviceManager: deviceManager, deviceAppMonitoringService: deviceAppMonitoringService)
    let settings = SettingsViewModel()
    
    return RecentAppsView(viewModel: viewModel, settings: settings)
        .frame(width: 320)
        .padding()
        .onAppear {
            viewModel.recentAppChanges = []
        }
}

// MARK: - Inline Mocks for Preview

private class InlineDeviceManager: DeviceManagerProtocol {
    private let _devices = CurrentValueSubject<[Device], Never>([])
    private let _deviceTypes = CurrentValueSubject<[DeviceType], Never>([])
    private let _recentAppChanges = CurrentValueSubject<[AppChange], Never>([])
    
    var devices: AnyPublisher<[Device], Never> { _devices.eraseToAnyPublisher() }
    var deviceTypes: AnyPublisher<[DeviceType], Never> { _deviceTypes.eraseToAnyPublisher() }
    var recentAppChanges: AnyPublisher<[AppChange], Never> { _recentAppChanges.eraseToAnyPublisher() }
    
    func updateDevices() {}
    func updateDeviceTypes() {}
    func getAllDevices() -> [Device] { [] }
    func getBooted() -> [Device] { [] }
    func getShutdown() -> [Device] { [] }
    func getDeviceType(for device: Device) -> DeviceType? { nil }
    func getDeviceByUdid(_ udid: String) -> Device? { nil }
    func updateSpecificDevice(_ updatedDevice: Device) {}
    func getDevice(withUdid udid: String) -> Device? { nil }
    func addAppChanges(_ changes: [AppChange]) {}
}

private func createInlineMockDevice() -> Device {
    return Device(
        udid: "preview-device-uuid",
        name: "iPhone 15 Pro",
        state: .running,
        simulatorPlatform: .iPhone,
        osVersion: "17.0",
    )
}

private struct InlineMockApp: SimulatorApp {
    let bundleDisplayName: String = "Sample App"
    let bundleIdentifier: String = "com.example.sampleapp"
    let bundleName: String = "SampleApp"
    let bundleShortVersionString: String = "1.0"
    let bundleVersion: String = "1"
    let executable: String = "SampleApp"
    let platform: String = "iOS"
    let platformVersion: String = "17.0"
    let signerIdentity: String = "Apple Development"
    let teamIdentifier: String = "ABCD1234"
    let hasUserDefaults: Bool = true
    
    var displayName: String { bundleDisplayName }
    var appDocumentsFolderURL: URL? { nil }
    var appPackageURL: URL? { nil }
    var iconName: String { "app.fill" }
}
