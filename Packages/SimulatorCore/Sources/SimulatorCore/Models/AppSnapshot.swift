//
//  AppSnapshot.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 05.09.26.
//

import Foundation

/// Which of an app's containers a snapshot payload was captured from.
public enum SnapshotContainerKind: Codable, Sendable, Hashable {
    case appData
    case appGroup(identifier: String)

    public var displayName: String {
        switch self {
        case .appData:
            "App Container"
        case let .appGroup(identifier):
            identifier
        }
    }
}

/// One container inside a snapshot, and where its payload sits.
public struct CapturedContainer: Codable, Sendable, Equatable, Identifiable {
    public let kind: SnapshotContainerKind
    /// Directory name under the snapshot's `containers` directory.
    ///
    /// Recorded rather than derived from the container's identity: an app group identifier is not
    /// a safe directory name, and a scheme that mangles one into a name has to be reversible for
    /// restore to find the payload again. A recorded name never has to be reversed.
    public let payloadDirectoryName: String
    public let byteSize: Int64

    public var id: String {
        payloadDirectoryName
    }
}

/// What a snapshot recorded about the app, the device and itself.
///
/// Written as JSON beside the payload. It is the only thing that survives every other part of the
/// system: the app can be uninstalled and the device erased, and the manifest still says what the
/// payload is and what it may safely be restored onto.
public struct AppSnapshotManifest: Codable, Sendable, Equatable {
    static let fileName = "manifest.json"
    static let containersDirectoryName = "containers"
    static let appDataPayloadDirectoryName = "app-data"

    public let id: String
    public let label: String
    public let bundleIdentifier: String
    public let appDisplayName: String
    public let appShortVersion: String?
    public let appBuildVersion: String?
    public let deviceUDID: String
    public let deviceName: String
    public let osVersion: String
    public let createdAt: Date
    /// Whether `Library/Caches` and `tmp` are part of the payload. Restore needs this to know
    /// which parts of the live container it must leave alone.
    public let includesCaches: Bool
    /// What the payload holds. Restore and a live diff touch only these files, so a narrower
    /// snapshot never wipes or reports the rest of the container.
    public let contents: SnapshotContents
    public let totalByteSize: Int64
    public let containers: [CapturedContainer]
    /// Set on the snapshot a restore takes of the live container before overwriting it, so the
    /// list can tell an undo point apart from one the user deliberately created.
    public let isSafetySnapshot: Bool
}

extension AppSnapshotManifest {
    /// A manifest written before snapshots had contents holds the whole container, and decodes as
    /// ``SnapshotContents/everything`` so it restores and diffs exactly as it always did.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        appDisplayName = try container.decode(String.self, forKey: .appDisplayName)
        appShortVersion = try container.decodeIfPresent(String.self, forKey: .appShortVersion)
        appBuildVersion = try container.decodeIfPresent(String.self, forKey: .appBuildVersion)
        deviceUDID = try container.decode(String.self, forKey: .deviceUDID)
        deviceName = try container.decode(String.self, forKey: .deviceName)
        osVersion = try container.decode(String.self, forKey: .osVersion)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        includesCaches = try container.decode(Bool.self, forKey: .includesCaches)
        contents = try container.decodeIfPresent(SnapshotContents.self, forKey: .contents) ?? .everything
        totalByteSize = try container.decode(Int64.self, forKey: .totalByteSize)
        containers = try container.decode([CapturedContainer].self, forKey: .containers)
        isSafetySnapshot = try container.decode(Bool.self, forKey: .isSafetySnapshot)
    }

    /// The scope a restore or a live diff of this snapshot works on.
    var scope: SnapshotScope {
        SnapshotScope(contents: contents, includeCaches: includesCaches)
    }

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
public struct AppSnapshot: Sendable, Equatable, Identifiable {
    public let manifest: AppSnapshotManifest
    public let directoryURL: URL

    public var id: String {
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
///
/// Public so the app can resolve one on the main actor and hand it to ``AppSnapshotSaving``; its
/// contents stay internal.
public struct AppSnapshotTarget: Sendable, Equatable {
    public let bundleIdentifier: String
    public let appDisplayName: String
    let appShortVersion: String?
    let appBuildVersion: String?
    public let deviceUDID: String
    public let deviceName: String
    public let osVersion: String
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
    public init?(app: any SimulatorApp, device: Device) {
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

/// What a capture did about the running app before copying.
public enum AppTermination: Sendable, Equatable {
    /// The caller asked to leave the app running.
    case notRequested
    case terminated
    case notRunning
    /// Reported rather than fatal, as for restore; the capture went ahead regardless.
    case failed(message: String)
}

/// A finished capture, and whether the app was stopped for it.
public struct SnapshotCapture: Sendable, Equatable {
    public let snapshot: AppSnapshot
    public let termination: AppTermination
}

/// A difference between a snapshot and the app it is about to be restored onto.
///
/// Reported rather than acted on: the service has no business deciding whether a mismatch is
/// acceptable, and the confirmation the user sees already exists in the app's `DestructiveActionConfirming`.
public enum SnapshotRestoreWarning: Sendable, Equatable {
    case appShortVersionMismatch(snapshot: String?, target: String?)
    case appBuildVersionMismatch(snapshot: String?, target: String?)
    case osVersionMismatch(snapshot: String, target: String)
    /// A container the snapshot captured no longer exists on the target — an app group that was
    /// removed since. It is skipped rather than recreated.
    case containerMissingOnTarget(SnapshotContainerKind)

    public var message: String {
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
public struct SnapshotRestorePlan: Sendable, Equatable {
    public let snapshot: AppSnapshot
    public let target: AppSnapshotTarget
    public let warnings: [SnapshotRestoreWarning]

    public var hasWarnings: Bool {
        !warnings.isEmpty
    }
}

/// How far a capture or restore has got, for a caller driving an indicator.
public struct SnapshotProgress: Sendable, Equatable {
    public let copiedByteCount: Int64
    public let totalByteCount: Int64
    public let currentRelativePath: String

    public var fractionCompleted: Double {
        guard totalByteCount > 0 else {
            return 0
        }

        return min(1, Double(copiedByteCount) / Double(totalByteCount))
    }
}

public enum AppSnapshotError: LocalizedError, Equatable {
    case storageUnavailable
    case bundleIdentifierMismatch(snapshot: String, target: String)
    case missingPayload(containerName: String)
    case unreadableManifest(snapshotID: String)
    case nothingToCapture
    /// A narrower snapshot found none of the files it is limited to.
    case nothingInContents(SnapshotContents)

    public var errorDescription: String? {
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
        case let .nothingInContents(contents):
            "This app has no \(Self.describe(contents)) to snapshot."
        }
    }

    private static func describe(_ contents: SnapshotContents) -> String {
        switch (contents.includes(.databases), contents.includes(.userDefaults)) {
        case (true, true):
            "database or UserDefaults"
        case (true, false):
            "database"
        case (false, _):
            "UserDefaults"
        }
    }
}
