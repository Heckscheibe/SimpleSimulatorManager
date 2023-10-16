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
    private var simulatorFolderPath: URL? {
        let libraryPath = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
        return libraryPath.first?.appending(path: "Developer/CoreSimulator/Devices")
    }

    private let devicePlistName = "device.plist"
    
    @Published var deviceTypes: [DeviceType] = []
    @Published var devices: [Device] = []
    
    init() {
        loadDevices()
        bindDevices()
    }
}

private extension DeviceManager {
    func loadDevices() {
        let urls = getDeviceUrls()
        self.devices = urls.reduce(into: []) { devices, folderPath in
            let path = folderPath.appendingPathComponent(devicePlistName)
                
            do {
                let data = try Data(contentsOf: path)
                let decoder = PropertyListDecoder()
                var device = try decoder.decode(Device.self, from: data)
                device.folderPath = folderPath
                devices.append(device)
                os_log("Did load device: \(device.name)")
            } catch {
                os_log("Failed to load device due to error: \(error) at path: \(path)")
            }
        }
    }
    
    func bindDevices() {
        $devices.map { Set($0.map { DeviceType(id: $0.name) }).sorted() }
            .assign(to: &$deviceTypes)
    }
    
    func getDeviceUrls() -> [URL] {
        guard let path = simulatorFolderPath else {
            return []
        }
        do {
            let urls = try FileManager.default
                .contentsOfDirectory(at: path, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent != ".DS_Store" }
            os_log("did load content: \(urls)")
                
            return urls
        } catch {
            os_log("Failed to load content due to error \(error)")
            return []
        }
    }
}
