//
//  SimulatorManagerApp.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 11.10.23.
//

import SwiftUI

@main struct SimulatorManagerApp: App {
    // 1
    @State var currentNumber: String = "1"
    let manager = DeviceManager()
    
    var body: some Scene {
        // 2
        MenuBarExtra(currentNumber, systemImage: "iphone.gen3") {
            // 3
            Button("One") {
                currentNumber = "1"
            }
            Button("Two") {
                currentNumber = "2"
            }
            Button("Three") {
                currentNumber = "3"
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }.keyboardShortcut("q")
        }
    }
}
