//
//  ResetSimulatorsView.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 25.08.25.
//

import SwiftUI

struct ResetSimulatorsView: View {
    let viewModel: ResetSimulatorsViewModel

    var body: some View {
        Menu {
            if viewModel.isResettingSimulators {
                Text("Resetting...")
            } else {
                Button("Confirm Reset All Simulators", role: .destructive) {
                    viewModel.resetAllSimulators()
                }
            }
        } label: {
            buttonLabel
        }
        .disabled(viewModel.isResettingSimulators)
    }

    @ViewBuilder
    private var buttonLabel: some View {
        Image(systemName: viewModel.resetButtonIcon)
        Text(viewModel.resetButtonText)
    }
}
