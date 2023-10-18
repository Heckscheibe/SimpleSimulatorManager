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
            let path = url.appendingPathComponent(devicePlistName)
                
            do {
                var device: Device = try decodePlistsFile(at: path)
                device.folderURL = url
                devices.append(device)
                os_log("Did load device: \(device.name)")
            } catch {
                os_log("Failed to load device due to error: \(error) at path: \(path)")
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
        guard let appFolderPath = device.folderURL?
            .appendingPathComponent(SimulatorApp.appsPath) else {
            return
        }
        let urls = getContentOfDirectoryAt(url: appFolderPath)
    }
    
    func getContentOfDirectoryAt(url: URL) -> [URL] {
        guard FileManager.default.directoryExistsAtURL(url) else {
            return []
        }
        
        do {
            let urls = try FileManager.default
                .contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent != ".DS_Store" }
            os_log("did load content: \(urls)")
            return urls
        } catch {
            os_log("Failed to get content at path \(url) due to error \(error)")
            return []
        }
    }
    
    func decodePlistsFile<T: Decodable>(at path: URL) throws -> T {
        let decoder = PropertyListDecoder()
        let data = try Data(contentsOf: path)
        let object = try decoder.decode(T.self, from: data)
        return object
    }
}
