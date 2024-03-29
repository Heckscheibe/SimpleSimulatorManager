//
//  DeviceManager.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 13.10.23.
//

import Foundation
import Combine
import os

enum SimulatorPaths {
    static let appPackagePath = "data/Containers/Bundle/Application"
    static let appDataPath = "data/Containers/Data/Application"
    static let userDefaultsPath = "Library/Preferences"
}

class DeviceManager {
    @Published var deviceTypes: [DeviceType] = []
    @Published var devices: [Device] = []
    
    init() {
        loadDevices()
        bindDeviceTypes()
    }
    
    func update(device: Device) {
        loadApps(for: device)
        loadAppGroups(for: device)
    }
}

private extension DeviceManager {
    var simulatorFolderURL: URL? {
        let libraryPath = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
        return libraryPath.first?.appending(path: "Developer/CoreSimulator/Devices")
    }
    
    func bindDeviceTypes() {
        $devices.map { Set($0.map { DeviceType(id: $0.name,
                                               simulatorPlatform: $0.simulatorPlatform) }).sorted() }
            .assign(to: &$deviceTypes)
    }
    
    func loadDevices() {
        guard let url = simulatorFolderURL else { return }
        let urls = getContentOfDirectoryAt(url: url)

        self.devices = urls.reduce(into: []) { devices, url in
            let url = url.appendingPathComponent(Device.devicePlistName)
                
            do {
                let device = try CustomPropertyListDecoder().decode(Device.self, at: url)
                devices.append(device)
            } catch {
                os_log("Failed to load device due to error: \(error) at path: \(url)")
            }
        }
        
        devices.forEach {
            loadApps(for: $0)
            loadAppGroups(for: $0)
        }
    }
    
    func loadApps(for device: Device) {
        guard device.hasAppsInstalled else {
            os_log("\(device.name) with \(device.osVersion) does not have any apps installed.")
            
            return
        }
        
        let infoPlists = loadAppInfoPlists(for: device)
        
        guard let appDataFolderURL = device.url?
            .appendingPathComponent(SimulatorPaths.appDataPath) else {
            return
        }
        let appDataFolderURLs = getContentOfDirectoryAt(url: appDataFolderURL)
        
        var apps: [any SimulatorApp] = []
        infoPlists.forEach { infoPlist in
            // using oldschool for in loop to be able to `break` and return early
            for url in appDataFolderURLs {
                let metaDataPlistURL = url.appendingPathComponent(MetaDataPlist.fileName)
                do {
                    let metaDataPlist = try CustomPropertyListDecoder().decode(MetaDataPlist.self, at: metaDataPlistURL)
                    
                    guard metaDataPlist.mcmMetadataIdentifier == infoPlist.cfBundleIdentifier else {
                        continue
                    }
                    let hasUserDefaults = !getContentOfDirectoryAt(url: url.appendingPathComponent(SimulatorPaths.userDefaultsPath)).isEmpty
                    let simulatorApp: any SimulatorApp
                    if infoPlist.isWatchApp {
                        simulatorApp = SimulatorWatchOSApp(displayName: infoPlist.cfBundleDisplayName ?? infoPlist.cfBundleName,
                                                           bundleIdentifier: infoPlist.cfBundleIdentifier,
                                                           appDocumentsFolderURL: metaDataPlist.url,
                                                           appPackageURL: infoPlist.url,
                                                           hasUserDefaults: hasUserDefaults,
                                                           companioniOSAppBundleIdentifier: infoPlist.wkCompanionAppBundleIdentifier)
                    } else {
                        simulatorApp = SimulatoriOSApp(displayName: infoPlist.cfBundleDisplayName ?? infoPlist.cfBundleName,
                                                       bundleIdentifier: infoPlist.cfBundleIdentifier,
                                                       appDocumentsFolderURL: metaDataPlist.url,
                                                       appPackageURL: infoPlist.url,
                                                       hasWatchApp: infoPlist.hasCompanionWatchApp,
                                                       hasUserDefaults: hasUserDefaults)
                    }
                    apps.append(simulatorApp)
                    
                } catch {
                    os_log("Failed to decode MetaDataPlist due to error: \(error)")
                }
            }
        }
        os_log("Device \(device.name) with \(device.osVersion) has the following apps installed: \(apps.map { $0.displayName })")
        device.apps = apps
        device.hasAppsInstalled = !apps.isEmpty
    }
    
    func loadAppInfoPlists(for device: Device) -> [AppInfoPlist] {
        guard let appPackageFolderPath = device.url?
            .appendingPathComponent(SimulatorPaths.appPackagePath) else {
            return []
        }
        let appPackageURLs = getContentOfDirectoryAt(url: appPackageFolderPath)
        
        let infoPlists = appPackageURLs.compactMap { url -> AppInfoPlist? in
            let appFolderContent = getContentOfDirectoryAt(url: url)
            guard let appBundle = appFolderContent.filter({ $0.path.hasSuffix(".app") }).first else {
                return nil
            }
            
            let hasCompanionWatchApp = getContentOfDirectoryAt(url: appBundle).contains { url in
                url.pathComponents.last == "Watch"
            }
            
            do {
                var infoPlist = try CustomPropertyListDecoder()
                    .decode(AppInfoPlist.self, at: appBundle.appendingPathComponent(AppInfoPlist.infoPlistFileName))
                infoPlist.hasCompanionWatchApp = hasCompanionWatchApp
                return infoPlist
            } catch {
                os_log("Failed to decode plist due to error: \(error)")
                return nil
            }
        }
        
        return infoPlists
    }
    
    func loadAppGroups(for device: Device) {
        guard let appGroupsFolderURL = device.appGroupsFolder else {
            return
        }
        
        let appGroupFolderURLs = getContentOfDirectoryAt(url: appGroupsFolderURL)
        let appGroups = appGroupFolderURLs.compactMap { url in
            let appGroupFilePath = url.appendingPathComponent(MetaDataPlist.fileName)
            do {
                let appGroupPlist = try CustomPropertyListDecoder().decode(AppGroupPlist.self, at: appGroupFilePath)
                
                let hasUserDefaults = !getContentOfDirectoryAt(url: url.appendingPathComponent(SimulatorPaths.userDefaultsPath)).isEmpty
                let appGroup = AppGroup(identifier: appGroupPlist.identifier,
                                        uuid: appGroupPlist.uuid,
                                        hasUserDefaults: hasUserDefaults,
                                        url: appGroupPlist.url)
                return appGroup
                
            } catch {
                os_log("Failed to decode AppGroup due to error: \(error)")
                return nil
            }
        }
        .filter { (appGroup: AppGroup) in
            device.apps
                .map { $0.bundleIdentifier }
                .contains(where: {
                    $0.contains(appGroup.name)
                })
        }
        
        device.appGroups = appGroups
    }
    
    func getContentOfDirectoryAt(url: URL) -> [URL] {
        guard FileManager.default.directoryExistsAtURL(url) else {
            return []
        }
        
        do {
            let urls = try FileManager.default
                .contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent != ".DS_Store" }
            return urls
        } catch {
            os_log("Failed to get content at path \(url) due to error \(error)")
            return []
        }
    }
}
