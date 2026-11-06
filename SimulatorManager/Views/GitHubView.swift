//
//  GitHubView.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller 12.08.25.
//

import SwiftUI

/// The project link, the version and the update check of the native menu.
struct GitHubView<Updater: AppUpdating>: View {
    let githubService: GithubService
    @ObservedObject var updater: Updater
    /// Defaults to the running bundle's version, and stays injectable for previews.
    var appVersion: String? = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

    var body: some View {
        VStack {
            Button("GitHub Project") {
                githubService.openGithubProject()
            }

            Divider()

            if let appVersion {
                Text("Version \(appVersion)")
            }

            if let pendingUpdateVersion = updater.pendingUpdateVersion {
                Button {
                    updater.checkForUpdates()
                } label: {
                    Text("Update Available")
                    Text("Version \(pendingUpdateVersion)")
                    Image(systemName: "info.circle.fill")
                }
                .disabled(!updater.canCheckForUpdates)
            } else {
                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
            }
        }
    }
}
