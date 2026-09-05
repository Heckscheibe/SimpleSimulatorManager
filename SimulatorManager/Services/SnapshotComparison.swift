//
//  SnapshotComparison.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 05.09.26.
//

import Foundation
import os

/// Compares two container states — two snapshot payloads, or a payload and a live container.
///
/// Blocking work; callers hop to ``AppSnapshotService``'s work queue first.
enum SnapshotComparison {
    /// Either side may be `nil`, meaning the container exists on only one of them.
    static func compare(
        oldContainerURL: URL?,
        newContainerURL: URL?,
        kind: SnapshotContainerKind,
        includeCaches: Bool
    ) -> SnapshotContainerDiff {
        let oldSizes = sizes(of: oldContainerURL, includeCaches: includeCaches)
        let newSizes = sizes(of: newContainerURL, includeCaches: includeCaches)

        var fileChanges: [SnapshotFileChange] = []
        var defaultsChanges: [SnapshotDefaultsChange] = []

        for relativePath in Set(oldSizes.keys).union(newSizes.keys).sorted() {
            let oldSize = oldSizes[relativePath]
            let newSize = newSizes[relativePath]

            if SnapshotDefaultsDiffer.isDefaultsPlist(relativePath) {
                let changes = SnapshotDefaultsDiffer.changes(
                    domain: SnapshotDefaultsDiffer.domain(ofRelativePath: relativePath),
                    oldURL: oldSize == nil ? nil : oldContainerURL?.appendingPathComponent(relativePath),
                    newURL: newSize == nil ? nil : newContainerURL?.appendingPathComponent(relativePath)
                )

                // `nil` means a side is not a readable property list. Reporting it as a plain file
                // change is less informative but true, which beats claiming it did not change.
                if let changes {
                    defaultsChanges.append(contentsOf: changes)

                    continue
                }

                os_log("Snapshot diff fell back to file comparison for %{public}@", relativePath)
            }

            if let change = fileChange(relativePath: relativePath,
                                       oldSize: oldSize,
                                       newSize: newSize,
                                       oldContainerURL: oldContainerURL,
                                       newContainerURL: newContainerURL) {
                fileChanges.append(change)
            }
        }

        return SnapshotContainerDiff(kind: kind, fileChanges: fileChanges, defaultsChanges: defaultsChanges)
    }

    private static func sizes(of containerURL: URL?, includeCaches: Bool) -> [String: Int64] {
        guard let containerURL, FileManager.default.directoryExistsAtURL(containerURL) else {
            return [:]
        }

        return SnapshotContainerFiles.fileSizesByRelativePath(in: containerURL, includeCaches: includeCaches)
    }

    /// Same size is not the same content, and a different modification date is not a change: a
    /// container's timestamps move for reasons that have nothing to do with what it holds. Content
    /// is decided by hash, and the hash is only paid for when the sizes already agree.
    private static func fileChange(
        relativePath: String,
        oldSize: Int64?,
        newSize: Int64?,
        oldContainerURL: URL?,
        newContainerURL: URL?
    ) -> SnapshotFileChange? {
        switch (oldSize, newSize) {
        case let (nil, .some(size)):
            return SnapshotFileChange(kind: .added, relativePath: relativePath, oldByteSize: nil, newByteSize: size)
        case let (.some(size), nil):
            return SnapshotFileChange(kind: .removed, relativePath: relativePath, oldByteSize: size, newByteSize: nil)
        case let (.some(old), .some(new)):
            guard old == new else {
                return SnapshotFileChange(kind: .modified,
                                          relativePath: relativePath,
                                          oldByteSize: old,
                                          newByteSize: new)
            }
            guard let oldContainerURL, let newContainerURL else {
                return nil
            }

            let oldHash = try? SnapshotContainerFiles.contentHash(of: oldContainerURL.appendingPathComponent(relativePath))
            let newHash = try? SnapshotContainerFiles.contentHash(of: newContainerURL.appendingPathComponent(relativePath))

            // An unreadable side is reported as modified rather than silently equal: "could not be
            // compared" and "did not change" must not look the same in a diff someone is using to
            // decide whether a write landed.
            guard let oldHash, let newHash, oldHash == newHash else {
                return SnapshotFileChange(kind: .modified,
                                          relativePath: relativePath,
                                          oldByteSize: old,
                                          newByteSize: new)
            }

            return nil
        case (nil, nil):
            return nil
        }
    }
}
