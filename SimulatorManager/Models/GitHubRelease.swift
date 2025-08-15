//
//  GitHubRelease.swift
//  SimulatorManager
//
//  Created on 09.08.25.
//

import Foundation

struct GitHubRelease: Codable {
    let id: Int
    let tagName: String
    let name: String
    let body: String
    let publishedAt: String
    let htmlUrl: String
    let prerelease: Bool
    let draft: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case tagName = "tag_name"
        case name
        case body
        case publishedAt = "published_at"
        case htmlUrl = "html_url"
        case prerelease
        case draft
    }
    
    /// Compare version strings (e.g., "1.2.3" vs "1.3.0")
    func isNewerThan(_ currentVersion: String) -> Bool {
        let cleanTagName = tagName.replacingOccurrences(of: "v", with: "")
        let cleanCurrentVersion = currentVersion.replacingOccurrences(of: "v", with: "")
        
        return cleanTagName.compare(cleanCurrentVersion, options: .numeric) == .orderedDescending
    }
}
