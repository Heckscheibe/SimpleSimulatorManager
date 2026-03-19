//
//  DeviceTypeView.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 30.11.23.
//

import Foundation
import SwiftUI

struct DeviceTypeView: View {
    let viewModel: SimulatorManagerViewModel
    @ObservedObject var settings: Settings
    
    var body: some View {
        ForEach(viewModel.deviceTypes.filter { settings.visiblePlatforms.contains($0.simulatorPlatform) }) { deviceType in
            Menu(deviceType.name) {
                ForEach(viewModel.devices.filter { $0.name == deviceType.name }) { device in
                    DeviceView(viewModel: viewModel.makeDeviceViewModel(for: device))
                }
            }
        }
    }
}
