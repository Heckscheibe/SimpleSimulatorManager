//
//  DeviceManager.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 13.10.23.
//

import Foundation
import Combine
import os

class DeviceManager {
    private var simulatorFolderURL: URL? {
        let libraryPath = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
        return libraryPath.first?.appending(path: "Developer/CoreSimulator/Devices")
    }

    @Published var deviceTypes: [DeviceType] = []
    @Published var devices: [Device] = []
    
    init() {
        loadDevices()
        bindDeviceTypes()
    }
}

private extension DeviceManager {
    func bindDeviceTypes() {
        $devices.map { Set($0.map { DeviceType(id: $0.name) }).sorted() }
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
                os_log("Did load device: \(device.name)")
            } catch {
                os_log("Failed to load device due to error: \(error) at path: \(url)")
            }
        }
        
        devices.forEach { loadApps(for: $0) }
    }
    
    func loadApps(for device: Device) {
        guard device.hasAppsInstalled else {
            os_log("\(device.name) with \(device.osVersion) does not have any apps installed.")
            
            return
        }
        
        let infoPlists = loadAppInfoPlists(for: device)
        
        guard let appDataFolderURL = device.url?
            .appendingPathComponent(SimulatorApp.appDataPath) else {
            return
        }
        let appDataFolderURLs = getContentOfDirectoryAt(url: appDataFolderURL)
        
        var apps: [SimulatorApp] = []
        infoPlists.forEach { infoPlist in
            // using oldschool for in loop to be able to `break` and return early
            for url in appDataFolderURLs {
                let metaDataPlistURL = url.appendingPathComponent(MetaDataPlist.fileName)
                do {
                    let metaDataPlist = try CustomPropertyListDecoder().decode(MetaDataPlist.self, at: metaDataPlistURL)
                    if metaDataPlist.mcmMetadataIdentifier == infoPlist.cfBundleIdentifier {
                        let simulatorApp = SimulatorApp(displayName: infoPlist.cfBundleDisplayName,
                                                        bundleIdentifier: infoPlist.cfBundleIdentifier,
                                                        appDocumentsFolderURL: metaDataPlist.url,
                                                        appPackageURL: infoPlist.url)
                        apps.append(simulatorApp)
                        break
                    }
                } catch {
                    os_log("Failed to decode MetaDataPlist due to error: \(error)")
                }
            }
        }
        os_log("Device \(device.name) with \(device.osVersion) has the following apps installed: \(apps.map { $0.displayName })")
        device.apps = apps
    }
    
    func loadAppInfoPlists(for device: Device) -> [AppInfoPlist] {
        guard let appPackageFolderPath = device.url?
            .appendingPathComponent(SimulatorApp.appPackagePath) else {
            return []
        }
        let appPackageURLs = getContentOfDirectoryAt(url: appPackageFolderPath)
        
        let infoPlists = appPackageURLs.compactMap { url -> AppInfoPlist? in
            let appFolderContent = getContentOfDirectoryAt(url: url)
            guard let appBundle = appFolderContent.filter({ $0.path.hasSuffix(".app") }).first else {
                return nil
            }
            os_log("\(appBundle.path)")
            do {
                let infoPlist = try CustomPropertyListDecoder()
                    .decode(AppInfoPlist.self, at: appBundle.appendingPathComponent("/\(AppInfoPlist.infoPlistFileName)"))
                os_log("Did load plist of app called \(infoPlist.cfBundleDisplayName)")
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
}
