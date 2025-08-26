//
//  ResetSimulatorsView.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 25.08.25.
//

import SwiftUI

struct ResetSimulatorsView: View {
    @ObservedObject var viewModel: SimulatorManagerViewModel
    
    var body: some View {
        Button {
            viewModel.resetAllSimulators()
        } label: {
            if viewModel.isResettingSimulators {
                HStack {
                    Text("Resetting...")
                }
            } else {
                Label("Reset All Simulators", systemImage: "arrow.clockwise")
            }
        }
        .disabled(viewModel.isResettingSimulators)
    }
}

#Preview {
    ResetSimulatorsView(viewModel: SimulatorManagerViewModel())
}
