//
//  ResetSimulatorsView.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 25.08.25.
//

import SwiftUI

struct ResetSimulatorsView: View {
    @ObservedObject var viewModel: ResetSimulatorsViewModel
    
    var body: some View {
        Button {
            viewModel.resetAllSimulators()
        } label: {
            if viewModel.isResettingSimulators {
                HStack {
                    Text("Resetting...")
                }
            } else {
                Image(systemName: "arrow.clockwise")
                Text("Reset All Simulators")
            }
        }
        .disabled(viewModel.isResettingSimulators)
    }
}

#Preview {
    ResetSimulatorsView(viewModel: ResetSimulatorsViewModel())
}
