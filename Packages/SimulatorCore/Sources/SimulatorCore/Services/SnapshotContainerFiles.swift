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

    /// Whether `relativePath` is outside what any snapshot captures, whatever its contents.
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
    static func fileSizesByRelativePath(in containerURL: URL, scope: SnapshotScope) -> [String: Int64] {
        entriesByRelativePath(in: containerURL, scope: scope)
            .filter { $0.value.isFile }
            .mapValues(\.byteSize)
    }

    /// Every entry of `containerURL` in `scope`, files and directories, keyed by relative path.
    static func entriesByRelativePath(in containerURL: URL, scope: SnapshotScope) -> [String: ContainerEntry] {
        var entriesByRelativePath: [String: ContainerEntry] = [:]

        enumerateContainer(at: containerURL, scope: scope) { _, relativePath, entry in
            entriesByRelativePath[relativePath] = entry
        }

        return entriesByRelativePath
    }

    // MARK: - Copying

    /// Copies the captured part of `containerURL` into `destinationURL`, which must not exist yet.
    /// - Returns: The number of bytes written.
    @discardableResult
    static func copyContainer(
        at containerURL: URL,
        to destinationURL: URL,
        scope: SnapshotScope,
        totalByteCount: Int64,
        progress: (@Sendable (SnapshotProgress) -> Void)? = nil
    ) throws -> Int64 {
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        var copiedByteCount: Int64 = 0
        var failure: Error?

        enumerateContainer(at: containerURL, scope: scope) { url, relativePath, entry in
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
        try copyPayload(at: payloadURL, into: containerURL, preservedRelativePaths: preservedRelativePaths)
    }

    /// Replaces only the files in `scope` — a databases-only or UserDefaults-only restore — and
    /// leaves everything else in `containerURL` alone.
    ///
    /// The live container is sorted with the same rules the capture used, so the two agree about
    /// what is in scope: a database created since the snapshot is removed, a document is not. Each
    /// database goes back as one unit with its companions, and anything the database would replay
    /// into the restored file — a stale `-wal`, a Realm's `.lock` and `.note` — is removed first.
    static func replaceScopedContents(
        of containerURL: URL,
        withContentsOf payloadURL: URL,
        scope: SnapshotScope
    ) throws {
        let liveEntries = entriesByRelativePath(in: containerURL, scope: scope)
        let payloadEntries = entriesByRelativePath(in: payloadURL, scope: scope)

        // Files first, then whatever directories that emptied, deepest first. A directory in scope
        // is a database's companion folder, and removing it file by file keeps the rule that a
        // restore never deletes a special file it happens to contain.
        for (relativePath, entry) in liveEntries where entry.isFile {
            try removeItemIfPresent(at: containerURL.appendingPathComponent(relativePath))
        }

        for (relativePath, entry) in liveEntries.sorted(by: { $0.key > $1.key }) where entry.isDirectory {
            let url = containerURL.appendingPathComponent(relativePath)

            if (try? FileManager.default.contentsOfDirectory(atPath: url.path))?.isEmpty == true {
                try removeItemIfPresent(at: url)
            }
        }

        // A database being restored, or one being removed, takes its companions and auxiliary files
        // with it even where the live main file is gone or was not recognised — a `-wal` left beside
        // a restored database would be replayed into it.
        let databases = (Array(liveEntries) + Array(payloadEntries)).compactMap { relativePath, entry in
            entry.databaseFormat.map { (relativePath: relativePath, format: $0) }
        }

        for database in databases {
            let directoryURL = containerURL
                .appendingPathComponent(database.relativePath)
                .deletingLastPathComponent()
            let mainFileName = (database.relativePath as NSString).lastPathComponent

            for name in database.format.companionNames(mainFileName) + database.format.auxiliaryNames(mainFileName) {
                try removeItemIfPresent(at: directoryURL.appendingPathComponent(name))
            }
        }

        // The snapshot's file wins at its own path even where the live file there no longer counts
        // as in scope — a database overwritten with something that is not one — or the copy would
        // fail on it halfway through the restore.
        for (relativePath, entry) in payloadEntries where entry.isFile {
            try removeItemIfPresent(at: containerURL.appendingPathComponent(relativePath))
        }

        try copyPayload(at: payloadURL, into: containerURL, preservedRelativePaths: [])
    }

    /// Writes every captured file of `payloadURL` into `containerURL`, whose matching paths must
    /// already have been cleared.
    private static func copyPayload(at payloadURL: URL, into containerURL: URL, preservedRelativePaths: Set<String>) throws {
        var failure: Error?

        // A payload only ever holds what its snapshot captured, so all of it goes back.
        enumerateContainer(at: payloadURL, scope: .everything(includeCaches: true)) { url, relativePath, entry in
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
        /// Set on a database's main file, and only by a walk whose scope is limited to databases.
        var databaseFormat: SnapshotDatabaseFormat?

        /// A symlink is copied as a link rather than followed, so it counts as a file here even
        /// when it points at a directory.
        var isFile: Bool {
            isSymbolicLink || !isDirectory
        }
    }

    /// Walks `containerURL`, skipping excluded subtrees without descending into them, and hands
    /// each entry in `scope` its path relative to that root.
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
    ///
    /// Special files are skipped here, so capture, restore and diff all agree that they do not
    /// exist — see ``isSpecialFile(_:)``. The same goes for scope: a narrower snapshot's rules are
    /// applied here and nowhere else — see ``memberships(of:contents:)``. A directory outside the
    /// scope is still searched, since a database can sit anywhere, but is not reported.
    static func enumerateContainer(
        at containerURL: URL,
        scope: SnapshotScope,
        body: (URL, String, ContainerEntry) -> Void
    ) {
        let resourceKeys = entryResourceKeys.union([.fileSizeKey])
        var pending: [(url: URL, relativePrefix: String, isWhollyInScope: Bool)] = [
            (containerURL, "", scope.contents == .everything)
        ]

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

            var candidates: [WalkCandidate] = []

            // Sorted so a snapshot's progress and a diff's output are the same on every run.
            for url in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let relativePath = directory.relativePrefix + url.lastPathComponent

                guard !isExcluded(relativePath, includeCaches: scope.includeCaches) else {
                    continue
                }

                let values = try? url.resourceValues(forKeys: resourceKeys)

                guard !isSpecialFile(values) else {
                    os_log("Snapshot skipped %{public}@; it is not a regular file, directory or symlink",
                           relativePath)

                    continue
                }

                let isSymbolicLink = values?.isSymbolicLink == true

                candidates.append(WalkCandidate(
                    url: url,
                    relativePath: relativePath,
                    isRegularFile: values?.isRegularFile == true,
                    entry: ContainerEntry(isDirectory: values?.isDirectory == true && !isSymbolicLink,
                                          isSymbolicLink: isSymbolicLink,
                                          byteSize: Int64(values?.fileSize ?? 0))
                ))
            }

            let memberships = directory.isWhollyInScope ? [:] : memberships(of: candidates, contents: scope.contents)

            for candidate in candidates {
                var entry = candidate.entry
                let isWhollyInScope: Bool

                let membership: Membership? = directory.isWhollyInScope ? .whole : memberships[candidate.relativePath]

                switch membership {
                case .whole:
                    isWhollyInScope = true
                case let .database(format):
                    entry.databaseFormat = format
                    isWhollyInScope = true
                case .auxiliary:
                    continue
                case nil:
                    // Searched for databases, but neither reported nor copied as a whole.
                    if entry.isDirectory {
                        pending.append((candidate.url, candidate.relativePath + "/", false))
                    }

                    continue
                }

                body(candidate.url, candidate.relativePath, entry)

                if entry.isDirectory {
                    pending.append((candidate.url, candidate.relativePath + "/", isWhollyInScope))
                }
            }
        }
    }

    /// One entry of a directory being walked, before scope has been decided.
    private struct WalkCandidate {
        let url: URL
        let relativePath: String
        let isRegularFile: Bool
        let entry: ContainerEntry
    }

    /// How an entry of a narrower snapshot's directory relates to its contents.
    private enum Membership {
        /// In scope, with everything under it.
        case whole
        /// A database's main file.
        case database(SnapshotDatabaseFormat)
        /// Beside a database, recreated by it, and never captured — Realm's `.lock` and friends.
        case auxiliary
    }

    /// The rules for which files a narrower snapshot holds, decided one directory at a time because
    /// a database's companions are found beside it.
    ///
    /// UserDefaults are the domain plists directly in `Library/Preferences` — the same rule the diff
    /// uses to read them key by key. Databases are found by content: each regular file's first
    /// ``SnapshotDatabaseFormat/headerByteCount`` bytes, never more, are checked against
    /// ``SnapshotDatabaseFormat/all``.
    private static func memberships(of candidates: [WalkCandidate], contents: SnapshotContents) -> [String: Membership] {
        var memberships: [String: Membership] = [:]

        if contents.includes(.userDefaults) {
            for candidate in candidates
                where candidate.entry.isFile && SnapshotDefaultsDiffer.isDefaultsPlist(candidate.relativePath) {
                memberships[candidate.relativePath] = .whole
            }
        }

        guard contents.includes(.databases) else {
            return memberships
        }

        let relativePaths = Set(candidates.map(\.relativePath))

        for candidate in candidates where candidate.isRegularFile && memberships[candidate.relativePath] == nil {
            let fileName = candidate.url.lastPathComponent

            guard let format = SnapshotDatabaseFormat.format(ofFileNamed: fileName,
                                                             header: header(of: candidate.url)) else {
                continue
            }

            memberships[candidate.relativePath] = .database(format)

            let directoryPrefix = String(candidate.relativePath.dropLast(fileName.count))

            for name in format.companionNames(fileName) where relativePaths.contains(directoryPrefix + name) {
                memberships[directoryPrefix + name] = .whole
            }

            for name in format.auxiliaryNames(fileName) where relativePaths.contains(directoryPrefix + name) {
                memberships[directoryPrefix + name] = .auxiliary
            }
        }

        return memberships
    }

    /// The first bytes of a file, or nothing when it cannot be read — which still lets a format that
    /// also goes by extension recognise it.
    private static func header(of url: URL) -> Data {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return Data()
        }

        defer {
            try? handle.close()
        }

        return (try? handle.read(upToCount: SnapshotDatabaseFormat.headerByteCount)) ?? Data()
    }

    private static let entryResourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .isRegularFileKey
    ]

    /// A named pipe, socket or device node: not app state, and `FileManager.copyItem` refuses to
    /// copy one, which would otherwise fail the whole snapshot. Realm keeps a `.realm.note` pipe
    /// beside its database, and it outlives the app, so this is routine rather than exotic.
    ///
    /// An entry whose values could not be read is not called special; it is left to the copy,
    /// which already tells a file that vanished mid-walk from a real failure.
    private static func isSpecialFile(_ values: URLResourceValues?) -> Bool {
        guard let values else {
            return false
        }

        return values.isRegularFile != true && values.isDirectory != true && values.isSymbolicLink != true
    }

    /// Deletes everything under `directoryURL` except the preserved paths and special files.
    ///
    /// Descends into every directory rather than removing it whole, and removes it only once it is
    /// empty: a pipe a running app is listening on may sit anywhere below it, and deleting one
    /// breaks that app without restoring anything, since a snapshot never holds one.
    private static func removeContents(
        of directoryURL: URL,
        relativePrefix: String,
        preservedRelativePaths: Set<String>
    ) throws {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(entryResourceKeys),
            options: []
        )

        for url in contents {
            let relativePath = relativePrefix + url.lastPathComponent

            if preservedRelativePaths.contains(relativePath) {
                continue
            }

            let values = try? url.resourceValues(forKeys: entryResourceKeys)

            if isSpecialFile(values) {
                continue
            }

            guard values?.isDirectory == true, values?.isSymbolicLink != true else {
                try FileManager.default.removeItem(at: url)

                continue
            }

            try removeContents(of: url,
                               relativePrefix: relativePath + "/",
                               preservedRelativePaths: preservedRelativePaths)

            // Whatever is left is preserved or special, and keeps its directory.
            if try FileManager.default.contentsOfDirectory(atPath: url.path).isEmpty {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    /// Asks about the entry itself rather than following it, so a dangling symlink or a pipe still
    /// counts as present.
    private static func removeItemIfPresent(at url: URL) throws {
        guard (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil else {
            return
        }

        try FileManager.default.removeItem(at: url)
    }

    private static func isMissingFileError(_ error: Error) -> Bool {
        let nsError = error as NSError

        return (nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoSuchFileError)
            || (nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOENT))
    }
}
