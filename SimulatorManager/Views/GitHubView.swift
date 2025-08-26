//
//  GitHubView.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller 12.08.25.
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
                        Text("Update Available")
                        Text("Version \(version)")
                        Image(systemName: "info.circle.fill")
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
