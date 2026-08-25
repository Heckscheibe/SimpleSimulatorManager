//
//  UserDefaultsExportService.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 25.08.26.
//

import Foundation
import os

/// Turns the plists in a container's `Library/Preferences` into readable JSON.
protocol UserDefaultsExporting: Sendable {
    /// - Parameters:
    ///   - url: The container's `Library/Preferences` directory.
    ///   - preferredPlistName: File name without extension of the plist that holds the subject's own
    ///     preferences — the bundle identifier for an app, the group identifier for an app group.
    /// - Returns: Pretty-printed JSON for the preferences found at `url`.
    func exportJSON(fromPreferencesDirectoryAt url: URL, preferredPlistName: String) throws -> String
}

struct UserDefaultsExportService: UserDefaultsExporting {
    enum ExportError: LocalizedError, Equatable {
        case noPreferencesFound
        case unreadablePreferences(fileName: String)

        var errorDescription: String? {
            switch self {
            case .noPreferencesFound:
                "No preferences file was found in this container."
            case let .unreadablePreferences(fileName):
                "\(fileName) could not be read as a property list."
            }
        }
    }

    func exportJSON(fromPreferencesDirectoryAt url: URL, preferredPlistName: String) throws -> String {
        let plistURLs = plistURLs(in: url)

        guard !plistURLs.isEmpty else {
            throw ExportError.noPreferencesFound
        }

        // An app writes its own preferences to `<identifier>.plist`; the other files in the folder
        // are system-managed ones the user did not ask for.
        if let preferredURL = plistURLs.first(where: { $0.deletingPathExtension().lastPathComponent == preferredPlistName }) {
            return try PropertyListJSONConverter.jsonString(from: propertyList(at: preferredURL))
        }
        if plistURLs.count == 1, let onlyURL = plistURLs.first {
            return try PropertyListJSONConverter.jsonString(from: propertyList(at: onlyURL))
        }

        return try PropertyListJSONConverter.jsonString(from: combinedPropertyList(of: plistURLs))
    }
}

private extension UserDefaultsExportService {
    func plistURLs(in directoryURL: URL) -> [URL] {
        guard FileManager.default.directoryExistsAtURL(directoryURL) else {
            return []
        }

        do {
            return try FileManager.default
                .contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "plist" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            os_log("Failed to list preferences at \(directoryURL) due to error: \(error)")

            return []
        }
    }

    func propertyList(at url: URL) throws -> Any {
        do {
            let data = try Data(contentsOf: url)

            return try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            os_log("Failed to read preferences at \(url) due to error: \(error)")

            throw ExportError.unreadablePreferences(fileName: url.lastPathComponent)
        }
    }

    /// Several plists and none of them the subject's own: key them by file name so nothing is
    /// silently dropped. Files that fail to decode are logged and skipped, but an export where
    /// nothing could be read is a failure rather than an empty document.
    func combinedPropertyList(of urls: [URL]) throws -> [String: Any] {
        var combined: [String: Any] = [:]
        var firstFailure: Error?

        for url in urls {
            do {
                combined[url.lastPathComponent] = try propertyList(at: url)
            } catch {
                firstFailure = firstFailure ?? error
            }
        }

        guard !combined.isEmpty else {
            throw firstFailure ?? ExportError.noPreferencesFound
        }

        return combined
    }
}
