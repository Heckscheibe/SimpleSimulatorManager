//
//  SnapshotContainerFiles.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 05.09.26.
//

import CryptoKit
import Foundation
import os

/// The filesystem half of snapshotting: walking a container, copying it, putting one back, and
/// fingerprinting it for a diff.
///
/// Split out from ``AppSnapshotService`` because all of it is pure filesystem work with no
/// knowledge of manifests, and because it is the part worth testing directly against fixture
/// directories.
///
/// Everything here blocks. Callers hop to a dedicated queue first — see the note on
/// ``AppSnapshotService``'s work queue.
enum SnapshotContainerFiles {
    /// The container's own metadata plist, which identifies the container to CoreSimulator.
    ///
    /// Never captured and never overwritten. Its contents belong to the container, not to the app
    /// state inside it, and restoring one container's metadata into another is how a container
    /// stops being discoverable at all.
    static let containerMetadataFileName = MetaDataPlist.fileName

    static let ignoredFileNames: Set<String> = [".DS_Store"]

    /// Paths, relative to the container root, that a snapshot leaves out unless caches are included.
    static func excludedRelativePaths(includeCaches: Bool) -> Set<String> {
        includeCaches ? [] : [SimulatorPaths.cachesPath, SimulatorPaths.temporaryPath]
    }

    /// Whether `relativePath` is outside what a snapshot captures.
    static func isExcluded(_ relativePath: String, includeCaches: Bool) -> Bool {
        if relativePath == containerMetadataFileName {
            return true
        }

        let name = (relativePath as NSString).lastPathComponent

        if ignoredFileNames.contains(name) {
            return true
        }

        return excludedRelativePaths(includeCaches: includeCaches).contains { excluded in
            relativePath == excluded || relativePath.hasPrefix(excluded + "/")
        }
    }

    // MARK: - Walking

    /// Every captured file under `containerURL`, keyed by its path relative to that root.
    ///
    /// Sizes only. Hashing every file to build an index would read the whole container twice for a
    /// diff that mostly resolves on size alone; the hash is computed later, and only for the files
    /// whose sizes match.
    static func fileSizesByRelativePath(in containerURL: URL, includeCaches: Bool) -> [String: Int64] {
        var sizesByRelativePath: [String: Int64] = [:]

        enumerateContainer(at: containerURL, includeCaches: includeCaches) { _, relativePath, entry in
            guard entry.isFile else {
                return
            }

            sizesByRelativePath[relativePath] = entry.byteSize
        }

        return sizesByRelativePath
    }

    // MARK: - Copying

    /// Copies the captured part of `containerURL` into `destinationURL`, which must not exist yet.
    /// - Returns: The number of bytes written.
    @discardableResult
    static func copyContainer(
        at containerURL: URL,
        to destinationURL: URL,
        includeCaches: Bool,
        totalByteCount: Int64,
        progress: (@Sendable (SnapshotProgress) -> Void)? = nil
    ) throws -> Int64 {
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        var copiedByteCount: Int64 = 0
        var failure: Error?

        enumerateContainer(at: containerURL, includeCaches: includeCaches) { url, relativePath, entry in
            guard failure == nil else {
                return
            }

            let target = destinationURL.appendingPathComponent(relativePath)

            do {
                if entry.isDirectory {
                    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                } else {
                    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                            withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: url, to: target)
                    copiedByteCount += entry.byteSize
                }
            } catch {
                // A file the simulator deleted mid-copy is routine and costs nothing worth
                // reporting; anything else means the payload would be incomplete, and an
                // incomplete snapshot is worse than none because it will be restored one day.
                guard isMissingFileError(error) else {
                    failure = error

                    return
                }

                os_log("Snapshot skipped %{public}@; it disappeared while copying", relativePath)
            }

            progress?(SnapshotProgress(copiedByteCount: copiedByteCount,
                                       totalByteCount: totalByteCount,
                                       currentRelativePath: relativePath))
        }

        if let failure {
            throw failure
        }

        return copiedByteCount
    }

    /// Replaces the contents of `containerURL` with `payloadURL`'s, leaving `preservedRelativePaths`
    /// and everything under them untouched.
    ///
    /// Removing first is the point: a restore that only overwrote the files it knows about would
    /// leave everything written since the snapshot in place, which is not the state that was
    /// captured.
    static func replaceContents(
        of containerURL: URL,
        withContentsOf payloadURL: URL,
        preservedRelativePaths: Set<String>
    ) throws {
        try removeContents(of: containerURL,
                           relativePrefix: "",
                           preservedRelativePaths: preservedRelativePaths)

        var failure: Error?

        enumerateContainer(at: payloadURL, includeCaches: true) { url, relativePath, entry in
            guard failure == nil, !preservedRelativePaths.contains(relativePath) else {
                return
            }

            let target = containerURL.appendingPathComponent(relativePath)

            do {
                if entry.isDirectory {
                    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                } else {
                    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                            withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: url, to: target)
                }
            } catch {
                failure = error
            }
        }

        if let failure {
            throw failure
        }
    }

    // MARK: - Hashing

    /// SHA-256 of a file, read in chunks so a large store never lands in memory whole.
    static func contentHash(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)

        defer {
            try? handle.close()
        }

        var hasher = SHA256()

        while let chunk = try handle.read(upToCount: hashChunkByteCount), !chunk.isEmpty {
            hasher.update(data: chunk)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static let hashChunkByteCount = 1024 * 1024
}

// MARK: - Enumeration

extension SnapshotContainerFiles {
    struct ContainerEntry {
        let isDirectory: Bool
        let isSymbolicLink: Bool
        let byteSize: Int64

        /// A symlink is copied as a link rather than followed, so it counts as a file here even
        /// when it points at a directory.
        var isFile: Bool {
            isSymbolicLink || !isDirectory
        }
    }

    /// Walks `containerURL`, skipping excluded subtrees without descending into them, and hands
    /// each entry its path relative to that root.
    ///
    /// Descends by hand rather than with `FileManager`'s directory enumerator, which reports fully
    /// resolved paths: a container reached through a symlinked parent — `/var` standing in for
    /// `/private/var` — cannot then have its relative paths recovered by trimming the root it was
    /// given, and `resolvingSymlinksInPath` normalises in the opposite direction, so there is no
    /// pair of forms that reliably agree. Carrying the relative path down the walk needs no path
    /// arithmetic at all, and keeps a symlink *inside* the container a link rather than following
    /// it to wherever it points.
    ///
    /// Errors from individual directories are logged and the walk continues: a booted simulator
    /// rewrites its own container while this runs, and one vanished cache folder is not a reason to
    /// abandon a snapshot.
    static func enumerateContainer(
        at containerURL: URL,
        includeCaches: Bool,
        body: (URL, String, ContainerEntry) -> Void
    ) {
        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        var pending: [(url: URL, relativePrefix: String)] = [(containerURL, "")]

        while let directory = pending.popLast() {
            let contents: [URL]

            do {
                contents = try FileManager.default.contentsOfDirectory(
                    at: directory.url,
                    includingPropertiesForKeys: Array(resourceKeys),
                    options: []
                )
            } catch {
                os_log("Snapshot could not enumerate %{public}@: %{public}@",
                       directory.url.path,
                       error.localizedDescription)

                continue
            }

            // Sorted so a snapshot's progress and a diff's output are the same on every run.
            for url in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let relativePath = directory.relativePrefix + url.lastPathComponent

                guard !isExcluded(relativePath, includeCaches: includeCaches) else {
                    continue
                }

                let values = try? url.resourceValues(forKeys: resourceKeys)
                let isSymbolicLink = values?.isSymbolicLink == true
                let isDirectory = values?.isDirectory == true && !isSymbolicLink

                body(url, relativePath, ContainerEntry(isDirectory: isDirectory,
                                                       isSymbolicLink: isSymbolicLink,
                                                       byteSize: Int64(values?.fileSize ?? 0)))

                if isDirectory {
                    pending.append((url, relativePath + "/"))
                }
            }
        }
    }

    /// Deletes everything under `directoryURL` except the preserved paths, descending only into
    /// directories that still contain one.
    private static func removeContents(
        of directoryURL: URL,
        relativePrefix: String,
        preservedRelativePaths: Set<String>
    ) throws {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        )

        for url in contents {
            let relativePath = relativePrefix + url.lastPathComponent

            if preservedRelativePaths.contains(relativePath) {
                continue
            }

            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            let isDirectory = values?.isDirectory == true && values?.isSymbolicLink != true
            let holdsPreservedDescendant = preservedRelativePaths.contains { $0.hasPrefix(relativePath + "/") }

            if isDirectory, holdsPreservedDescendant {
                try removeContents(of: url,
                                   relativePrefix: relativePath + "/",
                                   preservedRelativePaths: preservedRelativePaths)
            } else {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    private static func isMissingFileError(_ error: Error) -> Bool {
        let nsError = error as NSError

        return (nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoSuchFileError)
            || (nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOENT))
    }
}
