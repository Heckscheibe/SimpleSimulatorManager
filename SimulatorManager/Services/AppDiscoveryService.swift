//
//  AppDiscoveryService.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 11.07.25.
//

import Foundation
import os

/// Service responsible for discovering and loading simulator apps from device directories
class AppDiscoveryService {
    // MARK: - Public Methods
    
    func loadApps(for device: Device) {
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
                    break // Found matching app data, move to next info plist
                    
                } catch {
                    os_log("Failed to decode MetaDataPlist due to error: \(error)")
                }
            }
        }
        os_log("Device \(device.name) with \(device.osVersion) has the following apps installed: \(apps.map { $0.displayName })")
        device.apps = apps
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
    
    // MARK: - Private Methods
    
    private func loadAppInfoPlists(for device: Device) -> [AppInfoPlist] {
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
    
    private func getContentOfDirectoryAt(url: URL) -> [URL] {
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
