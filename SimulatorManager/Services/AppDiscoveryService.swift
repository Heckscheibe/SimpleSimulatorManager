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
    
    func loadApps(for device: Device) -> [any SimulatorApp] {
        let (apps, _) = loadAppsAndTimestamps(for: device)
        os_log("Device \(device.name) with \(device.osVersion) has the following apps installed: \(apps.map { $0.displayName })")
        return apps
    }
    
    /// Load apps with their installation timestamps for initial recent apps population
    func loadRecentInstalledApps(for device: Device) -> [AppChange] {
        let (_, appChanges) = loadAppsAndTimestamps(for: device)
        return appChanges
    }
    
    func loadAppGroups(for device: Device) -> [AppGroup] {
        guard let appGroupsFolderURL = device.appGroupsFolder else {
            return []
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
        return appGroups
    }
    
    /// Load apps and their corresponding app changes with timestamps
    /// Returns a tuple of (apps, appChanges) to avoid code duplication
    func loadAppsAndTimestamps(for device: Device) -> (apps: [any SimulatorApp], appChanges: [AppChange]) {
        let infoPlists = loadAppInfoPlists(for: device)
        
        guard let appDataFolderURL = device.appDataFolder else {
            return ([], [])
        }
        let appDataFolderURLs = getContentOfDirectoryAt(url: appDataFolderURL)
        
        var apps: [any SimulatorApp] = []
        var appChanges: [AppChange] = []
        
        infoPlists.forEach { infoPlist in
            // using oldschool for in loop to be able to `break` and return early
            for url in appDataFolderURLs {
                let metaDataPlistURL = url.appendingPathComponent(MetaDataPlist.fileName)
                do {
                    let metaDataPlist = try CustomPropertyListDecoder().decode(MetaDataPlist.self, at: metaDataPlistURL)
                    
                    // this is the check if we found the correct app data folder
                    // we check the mcmMetadataIdentifier against the infoPlist's bundle identifier
                    guard metaDataPlist.mcmMetadataIdentifier == infoPlist.cfBundleIdentifier else {
                        continue
                    }
                    
                    // Get the modification date of the app data folder
                    let timestamp = getFileModificationDate(url: url) ?? Date.distantPast
                    
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
                    
                    // Add to both collections
                    apps.append(simulatorApp)
                    let appChange = AppChange(app: simulatorApp, device: device, changeType: .installed, timestamp: timestamp)
                    appChanges.append(appChange)
                    break // Found matching app data, move to next info plist
                    
                } catch {
                    os_log("Failed to decode MetaDataPlist due to error: \(error)")
                }
            }
        }
        
        return (apps, appChanges)
    }
    
    func loadAppInfoPlists(for device: Device) -> [AppInfoPlist] {
        guard let appPackageFolderPath = device.appPackagesFolder else {
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
    
    /// Get the modification date of a file or directory
    func getFileModificationDate(url: URL) -> Date? {
        do {
            let resourceValues = try url.resourceValues(forKeys: [.contentModificationDateKey])
            return resourceValues.contentModificationDate
        } catch {
            os_log("Failed to get modification date for \(url) due to error: \(error)")
            return nil
        }
    }
}
