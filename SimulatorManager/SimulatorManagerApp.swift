//
//  SimulatorManagerApp.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 11.10.23.
//

import SwiftUI

@main struct SimulatorManagerApp: App {
    @State var currentNumber: String = "1"
    let manager = DeviceManager()
    
    var body: some Scene {
        MenuBarExtra(currentNumber, systemImage: "iphone.gen3") {
            ForEach(manager.deviceTypes) { deviceType in
                Menu(deviceType.name) {
                    ForEach(manager.devices.filter { $0.name == deviceType.name }) {
                        Menu($0.osVersion) {}
                    }
                }
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }.keyboardShortcut("q")
        }
    }
}
