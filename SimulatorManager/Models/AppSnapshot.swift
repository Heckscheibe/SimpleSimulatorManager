//
//  AppSnapshot.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 05.09.26.
//

import Foundation

/// Which of an app's containers a snapshot payload was captured from.
enum SnapshotContainerKind: Codable, Sendable, Hashable {
    case appData
    case appGroup(identifier: String)

    var displayName: String {
        switch self {
        case .appData:
            "App Container"
        case let .appGroup(identifier):
            identifier
        }
    }
}

/// One container inside a snapshot, and where its payload sits.
struct CapturedContainer: Codable, Sendable, Equatable, Identifiable {
    let kind: SnapshotContainerKind
    /// Directory name under the snapshot's `containers` directory.
    ///
    /// Recorded rather than derived from the container's identity: an app group identifier is not
    /// a safe directory name, and a scheme that mangles one into a name has to be reversible for
    /// restore to find the payload again. A recorded name never has to be reversed.
    let payloadDirectoryName: String
    let byteSize: Int64

    var id: String {
        payloadDirectoryName
    }
}

/// What a snapshot recorded about the app, the device and itself.
///
/// Written as JSON beside the payload. It is the only thing that survives every other part of the
/// system: the app can be uninstalled and the device erased, and the manifest still says what the
/// payload is and what it may safely be restored onto.
struct AppSnapshotManifest: Codable, Sendable, Equatable {
    static let fileName = "manifest.json"
    static let containersDirectoryName = "containers"
    static let appDataPayloadDirectoryName = "app-data"

    let id: String
    let label: String
    let bundleIdentifier: String
    let appDisplayName: String
    let appShortVersion: String?
    let appBuildVersion: String?
    let deviceUDID: String
    let deviceName: String
    let osVersion: String
    let createdAt: Date
    /// Whether `Library/Caches` and `tmp` are part of the payload. Restore needs this to know
    /// which parts of the live container it must leave alone.
    let includesCaches: Bool
    let totalByteSize: Int64
    let containers: [CapturedContainer]
    /// Set on the snapshot a restore takes of the live container before overwriting it, so the
    /// list can tell an undo point apart from one the user deliberately created.
    let isSafetySnapshot: Bool
}

extension AppSnapshotManifest {
    /// Timestamps are kept in JSON as ISO 8601 with milliseconds, which is readable and orders
    /// correctly in a plain listing but is not the full resolution of a `Date`.
    ///
    /// Capture rounds to that resolution up front, so the manifest held in memory is the same value
    /// that comes back off disk. Otherwise two snapshots taken in the same millisecond would sort
    /// one way before a reload and the other way after, and no equality check on a manifest could
    /// ever hold.
    static func persistableTimestamp(from date: Date = Date()) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1000).rounded() / 1000)
    }

    /// Not `Sendable`, but only ever read — the same treatment the rest of the app's shared
    /// formatters and publishers get.
    nonisolated(unsafe) static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return formatter
    }()
}

/// A snapshot on disk: its manifest, and the directory holding both.
struct AppSnapshot: Sendable, Equatable, Identifiable {
    let manifest: AppSnapshotManifest
    let directoryURL: URL

    var id: String {
        manifest.id
    }

    var containersDirectoryURL: URL {
        directoryURL.appendingPathComponent(AppSnapshotManifest.containersDirectoryName, isDirectory: true)
    }

    func payloadURL(for container: CapturedContainer) -> URL {
        containersDirectoryURL.appendingPathComponent(container.payloadDirectoryName, isDirectory: true)
    }
}

/// An app group's shared container on a specific device.
struct AppGroupContainer: Sendable, Equatable {
    let identifier: String
    let url: URL
}

/// Everything a capture, restore or live diff needs about the app it is acting on, resolved once
/// up front.
///
/// A value type rather than the `Device` and `SimulatorApp` reference types, because the service
/// does its work off the main actor and both of those are main-queue-mutated shared state.
struct AppSnapshotTarget: Sendable, Equatable {
    let bundleIdentifier: String
    let appDisplayName: String
    let appShortVersion: String?
    let appBuildVersion: String?
    let deviceUDID: String
    let deviceName: String
    let osVersion: String
    /// The app's data container root — the directory holding `Documents`, `Library` and `tmp`.
    let dataContainerURL: URL
    let appGroupContainers: [AppGroupContainer]
}

extension AppSnapshotTarget {
    /// Resolves a target from what discovery already found, so no container path is derived twice.
    ///
    /// Returns `nil` when the app has no data container, which is the one thing a snapshot cannot
    /// do without. `appDocumentsFolderURL` is the container *root* despite its name — see
    /// ``AppContainerShortcut``, which appends `Library/Preferences` to the same URL.
    init?(app: any SimulatorApp, device: Device) {
        guard let dataContainerURL = app.appDocumentsFolderURL else {
            return nil
        }

        self.init(
            bundleIdentifier: app.bundleIdentifier,
            appDisplayName: app.displayName,
            appShortVersion: app.shortVersion,
            appBuildVersion: app.buildVersion,
            deviceUDID: device.udid,
            deviceName: device.name,
            osVersion: device.osVersion,
            dataContainerURL: dataContainerURL,
            appGroupContainers: AppGroup.groups(in: device.appGroups, associatedWith: app)
                .compactMap { group in
                    group.url.map { AppGroupContainer(identifier: group.identifier, url: $0) }
                }
        )
    }
}

/// A difference between a snapshot and the app it is about to be restored onto.
///
/// Reported rather than acted on: the service has no business deciding whether a mismatch is
/// acceptable, and the confirmation the user sees already exists in ``DestructiveActionConfirming``.
enum SnapshotRestoreWarning: Sendable, Equatable {
    case appShortVersionMismatch(snapshot: String?, target: String?)
    case appBuildVersionMismatch(snapshot: String?, target: String?)
    case osVersionMismatch(snapshot: String, target: String)
    /// A container the snapshot captured no longer exists on the target — an app group that was
    /// removed since. It is skipped rather than recreated.
    case containerMissingOnTarget(SnapshotContainerKind)

    var message: String {
        switch self {
        case let .appShortVersionMismatch(snapshot, target):
            "App version differs: the snapshot was taken from \(Self.describe(snapshot)), the installed app is \(Self.describe(target))."
        case let .appBuildVersionMismatch(snapshot, target):
            "Build number differs: the snapshot was taken from \(Self.describe(snapshot)), the installed app is \(Self.describe(target))."
        case let .osVersionMismatch(snapshot, target):
            "OS version differs: the snapshot was taken on \(snapshot), the target simulator runs \(target)."
        case let .containerMissingOnTarget(kind):
            "\(kind.displayName) is in the snapshot but not on the target, and will be skipped."
        }
    }

    private static func describe(_ version: String?) -> String {
        guard let version, !version.isEmpty else {
            return "an unknown version"
        }

        return version
    }
}

/// A validated restore, ready to run.
///
/// Producing it is the only place a restore can be refused, so nothing is overwritten by a call
/// that was never going to be legal.
struct SnapshotRestorePlan: Sendable, Equatable {
    let snapshot: AppSnapshot
    let target: AppSnapshotTarget
    let warnings: [SnapshotRestoreWarning]

    var hasWarnings: Bool {
        !warnings.isEmpty
    }
}

/// How far a capture or restore has got, for a caller driving an indicator.
struct SnapshotProgress: Sendable, Equatable {
    let copiedByteCount: Int64
    let totalByteCount: Int64
    let currentRelativePath: String

    var fractionCompleted: Double {
        guard totalByteCount > 0 else {
            return 0
        }

        return min(1, Double(copiedByteCount) / Double(totalByteCount))
    }
}

enum AppSnapshotError: LocalizedError, Equatable {
    case storageUnavailable
    case bundleIdentifierMismatch(snapshot: String, target: String)
    case missingPayload(containerName: String)
    case unreadableManifest(snapshotID: String)
    case nothingToCapture

    var errorDescription: String? {
        switch self {
        case .storageUnavailable:
            "The snapshot folder in Application Support could not be created."
        case let .bundleIdentifierMismatch(snapshot, target):
            "This snapshot was taken from \(snapshot) and cannot be restored onto \(target)."
        case let .missingPayload(containerName):
            "The snapshot is incomplete: its \(containerName) payload is missing."
        case let .unreadableManifest(snapshotID):
            "Snapshot \(snapshotID) could not be read."
        case .nothingToCapture:
            "This app has no container to snapshot."
        }
    }
}
