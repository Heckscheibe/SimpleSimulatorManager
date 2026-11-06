//
//  GithubService.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller 09.08.25.
//

import Foundation
import AppKit

/// Opens the project page. Update checks are Sparkle's job, see ``SparkleAppUpdater``.
@MainActor
final class GithubService {
    private let projectURL = "https://github.com/Heckscheibe/SimpleSimulatorManager"

    func openGithubProject() {
        guard let url = URL(string: projectURL) else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}
