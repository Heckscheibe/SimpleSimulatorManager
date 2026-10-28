//
//  SnapshotDatabaseFormat.swift
//  SimulatorCore
//
//  Created by Nicolas Hiller on 21.10.26.
//

import Foundation

/// One database format a databases-only snapshot recognises: how to tell its main file, and which
/// files around that file belong to it.
///
/// Capture, restore and diff only ever ask these questions through ``all``, so supporting another
/// format — LevelDB, say — is one more entry, not new code paths in each of them.
struct SnapshotDatabaseFormat: Sendable {
    let name: String
    /// Whether a regular file is this format's main file, from its name and its first
    /// ``headerByteCount`` bytes (fewer when the file is shorter).
    let isMainFile: @Sendable (_ fileName: String, _ header: Data) -> Bool
    /// Files and folders beside the main file that are part of the database and travel with it:
    /// captured with it, and removed from the live container before it is restored, so a stale one
    /// is never replayed into the restored file. A folder is taken whole.
    let companionNames: @Sendable (_ mainFileName: String) -> [String]
    /// Files and folders beside the main file that are never captured, because the database
    /// recreates them, and are removed from the live container whenever the main file is restored
    /// or removed — they describe the file being replaced.
    let auxiliaryNames: @Sendable (_ mainFileName: String) -> [String]

    /// Enough for every header below. Detection never reads more of a file than this.
    static let headerByteCount = 24

    static let all: [SnapshotDatabaseFormat] = [.sqlite, .realm]

    /// Where iOS and its frameworks keep databases of their own in an app's container: URLSession's
    /// cookie and HSTS store, WebKit's website data, Safari view controller state and the launch
    /// snapshots. They are not the app's data, so a database snapshot neither captures nor restores
    /// them — restoring would otherwise delete a cookie store created after the capture.
    static let systemOwnedPaths: [String] = [
        "Library/HTTPStorages",
        "Library/WebKit",
        "Library/Safari",
        "Library/Cookies",
        "Library/SplashBoard",
        "Library/Application Support/.tipkit"
    ]

    /// URLCache's store, `Library/Caches/<bundle id>/Cache.db`, which only a snapshot that includes
    /// caches would otherwise find.
    static let urlCacheFileName = "Cache.db"

    /// Whether a container-relative path belongs to iOS rather than the app — see
    /// ``systemOwnedPaths``.
    static func isSystemOwned(_ relativePath: String) -> Bool {
        if systemOwnedPaths.contains(where: { relativePath == $0 || relativePath.hasPrefix($0 + "/") }) {
            return true
        }

        let components = relativePath.split(separator: "/")

        return components.count == 4
            && components[0] == "Library"
            && components[1] == "Caches"
            && components[3] == urlCacheFileName
    }

    /// The format whose main file this is, if any.
    static func format(ofFileNamed fileName: String, header: Data) -> SnapshotDatabaseFormat? {
        all.first { $0.isMainFile(fileName, header) }
    }
}

// MARK: - SQLite

extension SnapshotDatabaseFormat {
    /// SQLite, which is also Core Data, SwiftData, GRDB and FMDB.
    ///
    /// Recognised by content alone: SwiftData's `default.store` and GRDB files with no extension at
    /// all would be missed by an extension check, and a `.sqlite` that is not one would be picked.
    static let sqlite = SnapshotDatabaseFormat(
        name: "SQLite",
        isMainFile: { _, header in
            header.starts(with: sqliteHeader)
        },
        companionNames: { mainFileName in
            // A database without its `-wal` loses its recent writes or does not open, and Core Data
            // keeps large attributes in `.<store name>_SUPPORT` beside the store.
            let storeName = (mainFileName as NSString).deletingPathExtension

            return sqliteSidecarSuffixes.map { mainFileName + $0 } + [".\(storeName)_SUPPORT"]
        },
        auxiliaryNames: { _ in [] }
    )

    static let sqliteHeader = Data("SQLite format 3\0".utf8)
    static let sqliteSidecarSuffixes = ["-wal", "-shm", "-journal"]
}

// MARK: - Realm

extension SnapshotDatabaseFormat {
    /// Realm, recognised by the `T-DB` marker in its header, or by the `.realm` extension for an
    /// encrypted file, which is encrypted from its first page and has no readable marker.
    ///
    /// Only the `.realm` file is captured. Realm recreates its `.lock`, its `.note` pipe and its
    /// `.management` folder on the next open, and documents them as deletable while nothing has the
    /// file open — which a restore makes sure of by terminating the app first.
    static let realm = SnapshotDatabaseFormat(
        name: "Realm",
        isMainFile: { fileName, header in
            header.count >= realmMarkerRange.upperBound && header.subdata(in: realmMarkerRange) == realmMarker
                || (fileName as NSString).pathExtension == realmFileExtension
        },
        companionNames: { _ in [] },
        auxiliaryNames: { mainFileName in
            realmAuxiliarySuffixes.map { mainFileName + $0 }
        }
    )

    static let realmMarker = Data("T-DB".utf8)
    static let realmMarkerRange = 16 ..< 20
    static let realmFileExtension = "realm"
    static let realmAuxiliarySuffixes = [".lock", ".note", ".management"]
}
