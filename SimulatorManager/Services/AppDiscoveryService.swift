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
        return appGroupFolderURLs.compactMap { url in
            let appGroupFilePath = url.appendingPathComponent(MetaDataPlist.fileName)
            do {
                let appGroupPlist = try CustomPropertyListDecoder().decode(AppGroupPlist.self, at: appGroupFilePath)
                
                let hasUserDefaults = !getContentOfDirectoryAt(url: url.appendingPathComponent(SimulatorPaths.userDefaultsPath)).isEmpty
                return AppGroup(identifier: appGroupPlist.identifier,
                                uuid: appGroupPlist.uuid,
                                hasUserDefaults: hasUserDefaults,
                                url: appGroupPlist.url)
                
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
    }
    
    /// Load apps and their corresponding app changes with timestamps
    /// Returns a tuple of (apps, appChanges) to avoid code duplication
    func loadAppsAndTimestamps(for device: Device) -> (apps: [any SimulatorApp], appChanges: [AppChange]) {
        let infoPlists = loadAppInfoPlists(for: device)
        
        guard let appDataFolderURL = device.appDataFolder else {
            return ([], [])
        }

        let appDataFolderURLs = getContentOfDirectoryAt(url: appDataFolderURL)

        // Decode each data container's metadata exactly once and key it by identifier, so
        // matching apps to their containers is O(apps + containers) instead of O(apps x containers)
        // plist decodes. If two containers share an identifier (a stale one plus a fresh one),
        // keep the more recently modified.
        let containersByIdentifier = dataContainersByIdentifier(in: appDataFolderURLs)

        var apps: [any SimulatorApp] = []
        var appChanges: [AppChange] = []

        for infoPlist in infoPlists {
            guard let container = containersByIdentifier[infoPlist.cfBundleIdentifier] else {
                continue
            }

            // The app data folder changes when the container is touched; the .app bundle
            // directory is replaced on install/update. The newer of the two is the best
            // "last installed/updated" signal.
            let bundleDate = infoPlist.url.flatMap { getFileModificationDate(url: $0) }
            let timestamp = [container.modificationDate, bundleDate].compactMap { $0 }.max() ?? Date.distantPast

            let hasUserDefaults = !getContentOfDirectoryAt(url: container.folderURL.appendingPathComponent(SimulatorPaths.userDefaultsPath)).isEmpty
            let simulatorApp: any SimulatorApp
            if infoPlist.isWatchApp {
                simulatorApp = SimulatorWatchOSApp(displayName: infoPlist.cfBundleDisplayName ?? infoPlist.cfBundleName,
                                                   bundleIdentifier: infoPlist.cfBundleIdentifier,
                                                   appDocumentsFolderURL: container.metaDataPlist.url,
                                                   appPackageURL: infoPlist.url,
                                                   hasUserDefaults: hasUserDefaults,
                                                   companioniOSAppBundleIdentifier: infoPlist.wkCompanionAppBundleIdentifier,
                                                   contentModifiedAt: timestamp)
            } else {
                simulatorApp = SimulatoriOSApp(displayName: infoPlist.cfBundleDisplayName ?? infoPlist.cfBundleName,
                                               bundleIdentifier: infoPlist.cfBundleIdentifier,
                                               appDocumentsFolderURL: container.metaDataPlist.url,
                                               appPackageURL: infoPlist.url,
                                               hasWatchApp: infoPlist.hasCompanionWatchApp,
                                               hasUserDefaults: hasUserDefaults,
                                               contentModifiedAt: timestamp)
            }

            // Add to both collections
            apps.append(simulatorApp)
            let appChange = AppChange(app: simulatorApp, device: device, changeType: .installed, timestamp: timestamp)
            appChanges.append(appChange)
        }

        return (apps, appChanges)
    }

    /// A simulator data container plus the values derived from it once, so callers don't
    /// re-read the same metadata plist per app.
    private struct DataContainer {
        let metaDataPlist: MetaDataPlist
        let folderURL: URL
        let modificationDate: Date?
    }

    /// Decode every data container's metadata plist once, keyed by its `mcmMetadataIdentifier`.
    /// On duplicate identifiers the most recently modified container wins.
    private func dataContainersByIdentifier(in folderURLs: [URL]) -> [String: DataContainer] {
        var containersByIdentifier: [String: DataContainer] = [:]

        for url in folderURLs {
            let metaDataPlistURL = url.appendingPathComponent(MetaDataPlist.fileName)
            do {
                let metaDataPlist = try CustomPropertyListDecoder().decode(MetaDataPlist.self, at: metaDataPlistURL)
                let candidate = DataContainer(metaDataPlist: metaDataPlist,
                                              folderURL: url,
                                              modificationDate: getFileModificationDate(url: url))

                if let existing = containersByIdentifier[metaDataPlist.mcmMetadataIdentifier],
                   (existing.modificationDate ?? .distantPast) >= (candidate.modificationDate ?? .distantPast) {
                    continue
                }
                containersByIdentifier[metaDataPlist.mcmMetadataIdentifier] = candidate
            } catch {
                os_log("Failed to decode MetaDataPlist due to error: \(error)")
            }
        }

        return containersByIdentifier
    }
    
    func loadAppInfoPlists(for device: Device) -> [AppInfoPlist] {
        guard let appPackageFolderPath = device.appPackagesFolder else {
            return []
        }

        let appPackageURLs = getContentOfDirectoryAt(url: appPackageFolderPath)
        
        return appPackageURLs.compactMap { url -> AppInfoPlist? in
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
    }
    
    func getContentOfDirectoryAt(url: URL) -> [URL] {
        guard FileManager.default.directoryExistsAtURL(url) else {
            return []
        }
        
        do {
            return try FileManager.default
                .contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent != ".DS_Store" }
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
