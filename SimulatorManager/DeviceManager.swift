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

    private let devicePlistName = "device.plist"
    
    @Published var deviceTypes: [DeviceType] = []
    @Published var devices: [Device] = []
    
    init() {
        loadDevices()
        bindDeviceTypes()
    }
}

private extension DeviceManager {
    func loadDevices() {
        guard let url = simulatorFolderURL else { return }
        let urls = getContentOfDirectoryAt(url: url)

        self.devices = urls.reduce(into: []) { devices, url in
            let url = url.appendingPathComponent(devicePlistName)
                
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
    
    func bindDeviceTypes() {
        $devices.map { Set($0.map { DeviceType(id: $0.name) }).sorted() }
            .assign(to: &$deviceTypes)
    }
    
    func loadApps(for device: Device) {
        guard device.hasAppsInstalled else {
            os_log("\(device.name) with \(device.runtime) does not have any apps installed.")
            
            return
        }
        guard let appFolderPath = device.url?
            .appendingPathComponent(SimulatorApp.appsPath) else {
            return
        }
        let urls = getContentOfDirectoryAt(url: appFolderPath)
        
        let infoPlists = urls.compactMap { url -> AppInfoPlist? in
            let appFolderContent = getContentOfDirectoryAt(url: url)
            guard let appBundle = appFolderContent.filter({ $0.path.hasSuffix(".app") }).first else {
                return nil
            }
            os_log("\(appBundle.path)")
            do {
                let infoPlist: AppInfoPlist = try CustomPropertyListDecoder()
                    .decode(AppInfoPlist.self, at: appBundle.appendingPathComponent("/\(AppInfoPlist.infoPlistFileName)"))
                os_log("Did load plist of app called \(infoPlist.cfBundleDisplayName)")
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
            let urls = try FileManager.default
                .contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent != ".DS_Store" }
            return urls
        } catch {
            os_log("Failed to get content at path \(url) due to error \(error)")
            return []
        }
    }
    
    func decodePlistsFile<T: DecodableURLContainer>(at url: URL) throws -> T {
        try CustomPropertyListDecoder().decode(T.self, at: url)
    }
}

class CustomPropertyListDecoder: PropertyListDecoder {
    func decode<T>(_ type: T.Type, at url: URL) throws -> T where T: DecodableURLContainer {
        let data = try Data(contentsOf: url)
        var object = try decode(T.self, from: data)
        object.url = url
        return object
    }
}

protocol DecodableURLContainer: Decodable {
    var url: URL? { get set }
}
