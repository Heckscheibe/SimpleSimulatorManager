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
    ///   - ownDomain: The subject's standard defaults domain — the bundle identifier for an app,
    ///     the group identifier for an app group. It is always part of the export, even when the
    ///     name would otherwise look system-managed.
    ///   - domain: A single domain to export, or `nil` for every domain the container holds.
    /// - Returns: Pretty-printed JSON keyed by defaults domain, whether it holds one domain or six.
    func exportJSON(fromPreferencesDirectoryAt url: URL, ownDomain: String, domain: String?) throws -> String
}

/// One app writes more than one defaults domain: `UserDefaults.standard` lands in
/// `<bundle identifier>.plist`, and every `UserDefaults(suiteName:)` lands in `<suite name>.plist`
/// beside it — a real container routinely holds the app's own domain plus SDK suites such as
/// `APMAnalyticsSuiteName` or `com.firebase.FIRInstallations`.
///
/// There is no registry of an app's suites, and no way to tell a suite apart from a system domain
/// other than by name, so the export takes the container's whole `Library/Preferences` and keys it
/// by domain — see ``UserDefaultsDomain``. A caller after a single domain gets the same keyed
/// shape, so the document always says which domain it came from.
///
/// A suite named after an app group is the exception: it lives in the group container instead, and
/// is reached through the app group's own menu.
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

    func exportJSON(fromPreferencesDirectoryAt url: URL, ownDomain: String, domain requestedDomain: String?) throws -> String {
        let plistURLs = plistURLs(in: url)

        guard !plistURLs.isEmpty else {
            throw ExportError.noPreferencesFound
        }

        let exportedDomains = Set(requestedDomain.map { [$0] }
            ?? UserDefaultsDomain.appDomains(in: plistURLs.map { domain(of: $0) }, ownDomain: ownDomain))
        let exportedURLs = plistURLs.filter { exportedDomains.contains(domain(of: $0)) }

        // The menu was built from an earlier listing, so a domain named there can be gone by now.
        guard !exportedURLs.isEmpty else {
            throw ExportError.noPreferencesFound
        }

        return try PropertyListJSONConverter.jsonString(from: propertyListsByDomain(of: exportedURLs))
    }
}

private extension UserDefaultsExportService {
    func domain(of url: URL) -> String {
        UserDefaultsDomain.domain(ofPreferencesFileAt: url)
    }

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

    /// Keys every domain by its suite name. A single unreadable file is logged and skipped so the
    /// rest of the domains still make it out, but an export where nothing could be read is a
    /// failure rather than an empty document.
    func propertyListsByDomain(of urls: [URL]) throws -> [String: Any] {
        var propertyListsByDomain: [String: Any] = [:]
        var firstFailure: Error?

        for url in urls {
            do {
                propertyListsByDomain[domain(of: url)] = try propertyList(at: url)
            } catch {
                firstFailure = firstFailure ?? error
            }
        }

        guard !propertyListsByDomain.isEmpty else {
            throw firstFailure ?? ExportError.noPreferencesFound
        }

        return propertyListsByDomain
    }
}
