//
//  DeviceManager.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 13.10.23.
//

import Foundation
import Combine
import os

protocol DeviceProviding {
    var devices: AnyPublisher<[Device], Never> { get }
}

class DeviceManager {
    private var simulatorFolderPath: URL? {
        let libraryPath = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
        return libraryPath.first?.appending(path: "Developer/CoreSimulator/Devices")
    }
    
    @Published var deviceTypes: [DeviceType] = []
    
    private let devicesSubject = CurrentValueSubject<[Device], Never>([])
    
    private let devicePlistName = "device.plist"
    
    init() {
        loadDevices()
        bindDevices()
    }
}

extension DeviceManager: DeviceProviding {
    var devices: AnyPublisher<[Device], Never> {
        devicesSubject.eraseToAnyPublisher()
    }
}

private extension DeviceManager {
    func getDeviceUrls() -> [URL] {
        guard let path = simulatorFolderPath else {
            return []
        }
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: path, includingPropertiesForKeys: nil)
            os_log("did load content: \(urls)")
                
            return urls
        } catch {
            os_log("Failed to load content due to error \(error)")
            return []
        }
    }
    
    func bindDevices() {
        devices.map { Set($0.map { DeviceType(id: $0.name) }).sorted() }
            .assign(to: &$deviceTypes)
    }
    
    func loadDevices() {
        let urls = getDeviceUrls()
        var devices = [Device]()
        urls.forEach {
            let path = $0.appendingPathComponent(devicePlistName)
            
            do {
                let data = try Data(contentsOf: path)
                let decoder = PropertyListDecoder()
                let device = try decoder.decode(Device.self, from: data)
                devices.append(device)
                os_log("Did load device: \(device.name)")
            } catch {
                os_log("Failed to load device due to error: \(error) at path: \(path)")
            }
        }
        devicesSubject.send(devices)
    }
}
