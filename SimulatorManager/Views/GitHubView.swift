//
//  GitHubView.swift
//  SimulatorManager
//
//  Created on 12.08.25.
//

import SwiftUI

struct GitHubView: View {
    @StateObject private var githubService = GithubService()
    
    var body: some View {
        VStack {
            Button("GitHub Project") {
                githubService.openGithubProject()
            }
            
            if let version = Bundle.main.infoDictionary!["CFBundleShortVersionString"] as? String {
                Divider()
                if githubService.isUpdateAvailable {
                    Button {
                        githubService.openLatestRelease()
                    } label: {
                        Image(systemName: "info.circle.fill")
                            .symbolEffect(.bounce.up.byLayer, options: .repeat(.periodic(delay: 2.0)))
                        Text("Update Available")
                        Text("Version \(version)")
                    }
                } else {
                    Text("Version \(version)")
                }
            }
        }
        .onAppear {
            githubService.startPeriodicUpdateCheck()
        }
    }
}

#Preview {
    GitHubView()
}
