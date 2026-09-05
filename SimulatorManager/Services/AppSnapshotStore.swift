//
//  AppSnapshotStore.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 05.09.26.
//

import Foundation
import os

/// Where snapshots live and how they are listed, written and deleted.
///
/// Separate from ``AppSnapshotting`` so the layout is one thing rather than a set of paths built at
/// every call site, and so tests can point the whole feature at a throwaway directory.
protocol AppSnapshotStoring: Sendable {
    func snapshots(forBundleIdentifier bundleIdentifier: String) -> [AppSnapshot]
    func allSnapshots() -> [AppSnapshot]
    /// Total bytes across every snapshot on disk.
    func totalByteSize() -> Int64
    func delete(_ snapshot: AppSnapshot) throws
    /// Creates and returns an empty directory for a new snapshot.
    func makeSnapshotDirectory(bundleIdentifier: String, id: String) throws -> URL
    func write(_ manifest: AppSnapshotManifest, to directoryURL: URL) throws
    func readManifest(at directoryURL: URL) throws -> AppSnapshotManifest
    /// Removes a directory a failed capture left behind.
    func discardSnapshotDirectory(at directoryURL: URL)
}

/// Snapshots under `~/Library/Application Support/SimulatorManager/Snapshots/<bundle id>/<id>/`.
///
/// **Snapshot payloads are not protected.** They contain whatever the app persisted — access
/// tokens, session cookies, personal data — and sit unencrypted in Application Support, readable by
/// anything running as the user. That is the same protection the simulator container itself has,
/// but it now applies to a copy that deliberately outlives the simulator.
struct AppSnapshotStore: AppSnapshotStoring {
    private let rootURL: URL?

    /// - Parameter rootURL: Injectable so tests write to a throwaway directory instead of the
    ///   user's real Application Support.
    init(rootURL: URL? = SimulatorPaths.snapshotsRootURL()) {
        self.rootURL = rootURL
    }

    func snapshots(forBundleIdentifier bundleIdentifier: String) -> [AppSnapshot] {
        guard let bundleDirectoryURL = directoryURL(forBundleIdentifier: bundleIdentifier) else {
            return []
        }

        return sortedNewestFirst(loadSnapshots(in: bundleDirectoryURL))
    }

    func allSnapshots() -> [AppSnapshot] {
        guard let rootURL, FileManager.default.directoryExistsAtURL(rootURL) else {
            return []
        }

        let bundleDirectoryURLs = (try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return sortedNewestFirst(bundleDirectoryURLs.flatMap(loadSnapshots(in:)))
    }

    /// Sums the sizes the manifests recorded at capture time. A payload is never written to again
    /// once its manifest exists, so the recorded number cannot drift from what is on disk, and
    /// re-walking every snapshot to answer "how much space is this costing me" would be a full
    /// directory scan for a number that is already known.
    func totalByteSize() -> Int64 {
        allSnapshots().reduce(0) { $0 + $1.manifest.totalByteSize }
    }

    func delete(_ snapshot: AppSnapshot) throws {
        try FileManager.default.removeItem(at: snapshot.directoryURL)

        // A bundle directory with no snapshots left is litter, and an empty one would keep showing
        // an app in any listing built from the directory names.
        let bundleDirectoryURL = snapshot.directoryURL.deletingLastPathComponent()
        let remaining = (try? FileManager.default.contentsOfDirectory(atPath: bundleDirectoryURL.path)) ?? []

        if remaining.isEmpty {
            try? FileManager.default.removeItem(at: bundleDirectoryURL)
        }
    }

    func makeSnapshotDirectory(bundleIdentifier: String, id: String) throws -> URL {
        guard let bundleDirectoryURL = directoryURL(forBundleIdentifier: bundleIdentifier) else {
            throw AppSnapshotError.storageUnavailable
        }

        let snapshotDirectoryURL = bundleDirectoryURL.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: snapshotDirectoryURL, withIntermediateDirectories: true)

        return snapshotDirectoryURL
    }

    func write(_ manifest: AppSnapshotManifest, to directoryURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(AppSnapshotManifest.dateFormatter.string(from: date))
        }

        let data = try encoder.encode(manifest)
        try data.write(to: directoryURL.appendingPathComponent(AppSnapshotManifest.fileName))
    }

    func readManifest(at directoryURL: URL) throws -> AppSnapshotManifest {
        let manifestURL = directoryURL.appendingPathComponent(AppSnapshotManifest.fileName)

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let string = try decoder.singleValueContainer().decode(String.self)

                guard let date = AppSnapshotManifest.dateFormatter.date(from: string) else {
                    throw DecodingError.dataCorrupted(
                        DecodingError.Context(codingPath: decoder.codingPath,
                                              debugDescription: "\(string) is not an ISO 8601 date")
                    )
                }

                return date
            }

            return try decoder.decode(AppSnapshotManifest.self, from: Data(contentsOf: manifestURL))
        } catch {
            os_log("Failed to read snapshot manifest at %{public}@: %{public}@",
                   manifestURL.path,
                   error.localizedDescription)

            throw AppSnapshotError.unreadableManifest(snapshotID: directoryURL.lastPathComponent)
        }
    }

    func discardSnapshotDirectory(at directoryURL: URL) {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}

private extension AppSnapshotStore {
    /// Bundle identifiers are dotted reverse-DNS and contain nothing a path separator would split,
    /// so they are used as directory names as-is. Anything that would escape the root is refused
    /// rather than sanitised, because a sanitised name cannot be mapped back to its app.
    func directoryURL(forBundleIdentifier bundleIdentifier: String) -> URL? {
        guard let rootURL,
              !bundleIdentifier.isEmpty,
              !bundleIdentifier.contains("/"),
              bundleIdentifier != ".",
              bundleIdentifier != ".." else {
            return nil
        }

        return rootURL.appendingPathComponent(bundleIdentifier, isDirectory: true)
    }

    /// A directory whose manifest cannot be read is skipped rather than reported as a snapshot: it
    /// is not restorable, and offering it would only produce a failure later, at the point where
    /// the user is expecting their data back.
    func loadSnapshots(in bundleDirectoryURL: URL) -> [AppSnapshot] {
        guard FileManager.default.directoryExistsAtURL(bundleDirectoryURL) else {
            return []
        }

        let snapshotDirectoryURLs = (try? FileManager.default.contentsOfDirectory(
            at: bundleDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return snapshotDirectoryURLs.compactMap { url in
            guard let manifest = try? readManifest(at: url) else {
                return nil
            }

            return AppSnapshot(manifest: manifest, directoryURL: url)
        }
    }

    func sortedNewestFirst(_ snapshots: [AppSnapshot]) -> [AppSnapshot] {
        snapshots.sorted { lhs, rhs in
            if lhs.manifest.createdAt != rhs.manifest.createdAt {
                return lhs.manifest.createdAt > rhs.manifest.createdAt
            }

            return lhs.manifest.id < rhs.manifest.id
        }
    }
}
