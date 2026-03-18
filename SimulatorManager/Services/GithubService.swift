//
//  GithubService.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller 09.08.25.
//

import Foundation
import AppKit

@MainActor
class GithubService: ObservableObject {
    @Published var isUpdateAvailable = false
    var latestRelease: GitHubRelease?
    var isChecking = false
    
    private let apiURL = "https://api.github.com/repos/Heckscheibe/SimpleSimulatorManager/releases/latest"
    private let projectURL = "https://github.com/Heckscheibe/SimpleSimulatorManager"
    
    func openLatestRelease() {
        guard let release = latestRelease,
              let url = URL(string: release.htmlUrl) else {
            return
        }
        
        NSWorkspace.shared.open(url)
    }
    
    func openGithubProject() {
        guard let url = URL(string: projectURL) else {
            return
        }
        
        NSWorkspace.shared.open(url)
    }
    
    /// Check for updates periodically (e.g., every 24 hours)
    func startPeriodicUpdateCheck() {
        Task {
            // Check immediately
            await checkForUpdates()
            
            // Then check every 24 hours
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 24 * 60 * 60 * 1_000_000_000) // 24 hours in nanoseconds
                await checkForUpdates()
            }
        }
    }
}

private extension GithubService {
    func checkForUpdates() async {
        guard !isChecking else {
            return
        }
        
        isChecking = true
        
        guard let url = URL(string: apiURL) else {
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("SimulatorManager/1.0", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            self.handleReleaseResponse(release)
            isChecking = false
        } catch {
            print("Update check failed: \(error)")
            isChecking = false
        }
    }
    
    func handleReleaseResponse(_ release: GitHubRelease) {
        // Skip drafts and prereleases
        guard !release.draft, !release.prerelease else {
            return
        }
        
        let currentVersion = getCurrentAppVersion()
        let hasNewerVersion = release.isNewerThan(currentVersion)
        
        if hasNewerVersion {
            latestRelease = release
            isUpdateAvailable = true
            print("Update available: \(release.tagName) (current: \(currentVersion))")
        } else {
            isUpdateAvailable = false
            latestRelease = nil
        }
    }
    
    func getCurrentAppVersion() -> String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
}
