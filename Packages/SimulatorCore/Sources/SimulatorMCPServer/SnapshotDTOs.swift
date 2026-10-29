//
//  SnapshotDTOs.swift
//  SimulatorMCPServer
//

import Foundation
import SimulatorCore

// What the snapshot tools return. A snapshot's payload never appears in a result: files are listed
// by path and size, and UserDefaults values only with `--allow-user-defaults`.

public struct SnapshotDTO: Codable, Sendable, Equatable {
    /// Pass this to `diff_snapshot`, `restore_snapshot` and `delete_snapshot`.
    public let id: String
    public let bundleIdentifier: String
    public let label: String
    public let createdAt: Date
    public let appShortVersion: String?
    public let appBuildVersion: String?
    public let deviceUdid: String
    public let deviceName: String
    public let osVersion: String
    public let byteSize: Int64
    /// `appData`, or an app group identifier.
    public let containers: [String]
    /// The same names `capture_snapshot` takes: `everything`, `databases`, `userDefaults` or
    /// `databasesAndUserDefaults`.
    public let contents: String
    public let includesCaches: Bool
    public let isSafetySnapshot: Bool

    public init(snapshot: AppSnapshot) {
        let manifest = snapshot.manifest
        id = manifest.id
        bundleIdentifier = manifest.bundleIdentifier
        label = manifest.label
        createdAt = manifest.createdAt
        appShortVersion = manifest.appShortVersion
        appBuildVersion = manifest.appBuildVersion
        deviceUdid = manifest.deviceUDID
        deviceName = manifest.deviceName
        osVersion = manifest.osVersion
        byteSize = manifest.totalByteSize
        containers = manifest.containers.map(\.kind.identifier)
        contents = manifest.contents.identifier
        includesCaches = manifest.includesCaches
        isSafetySnapshot = manifest.isSafetySnapshot
    }
}

public struct SnapshotCaptureDTO: Codable, Sendable, Equatable {
    public let snapshot: SnapshotDTO
    /// `terminated`, `notRunning`, `notRequested` or `failed`.
    public let appTermination: String
    public let warnings: [String]

    public init(capture: SnapshotCapture) {
        snapshot = SnapshotDTO(snapshot: capture.snapshot)
        appTermination = capture.termination.identifier

        switch capture.termination {
        case .terminated, .notRunning:
            warnings = []
        case .notRequested:
            warnings = ["The app was left running, so a database it was writing to may have been captured mid-write."]
        case let .failed(message):
            warnings = ["The app could not be terminated (\(message)), so a database it was writing to may have been captured mid-write."]
        }
    }
}

extension AppTermination {
    /// `terminated`, `notRunning`, `notRequested` or `failed`, as the snapshot tools report it.
    var identifier: String {
        switch self {
        case .terminated: "terminated"
        case .notRunning: "notRunning"
        case .notRequested: "notRequested"
        case .failed: "failed"
        }
    }
}

public struct SnapshotRestoreDTO: Codable, Sendable, Equatable {
    /// False when warnings stopped the restore before anything was written.
    public let restored: Bool
    public let snapshot: SnapshotDTO
    public let udid: String
    public let warnings: [String]
    /// Restore this to undo the restore.
    public let safetySnapshotId: String?
    /// `terminated`, `notRunning` or `failed`; absent when nothing was restored.
    public let appTermination: String?
    public let message: String

    public init(
        restored: Bool,
        snapshot: SnapshotDTO,
        udid: String,
        warnings: [String],
        safetySnapshotId: String?,
        appTermination: String? = nil,
        message: String
    ) {
        self.restored = restored
        self.snapshot = snapshot
        self.udid = udid
        self.warnings = warnings
        self.safetySnapshotId = safetySnapshotId
        self.appTermination = appTermination
        self.message = message
    }
}

public struct SnapshotDiffDTO: Codable, Sendable, Equatable {
    public struct Summary: Codable, Sendable, Equatable {
        public let filesAdded: Int
        public let filesRemoved: Int
        public let filesModified: Int
        public let userDefaultsChanges: Int
    }

    public struct FileChange: Codable, Sendable, Equatable {
        /// `added`, `removed` or `modified`.
        public let change: String
        public let path: String
        public let oldByteSize: Int64?
        public let newByteSize: Int64?
    }

    public struct DefaultsChange: Codable, Sendable, Equatable {
        /// `added`, `removed` or `changed`.
        public let change: String
        public let domain: String
        public let key: String
        public let oldValue: String?
        public let newValue: String?
    }

    public struct ContainerDiff: Codable, Sendable, Equatable {
        /// `appData`, or an app group identifier.
        public let container: String
        public let files: [FileChange]
        public let userDefaults: [DefaultsChange]
    }

    public let snapshotId: String
    public let againstSnapshotId: String?
    /// The device whose live containers were compared, for `against_live`.
    public let againstLiveUdid: String?
    /// What both sides hold, and so what was compared — a narrower snapshot leaves the rest out.
    public let comparedContents: String
    public let hasChanges: Bool
    /// Counts over every change, including any cut by `limit`.
    public let summary: Summary
    /// True when `limit` cut the file lists.
    public let truncated: Bool
    public let containers: [ContainerDiff]
    /// Why UserDefaults values are missing, when they are.
    public let userDefaultsValuesNote: String?

    /// - Parameters:
    ///   - limit: The most file changes listed across all containers, in path order. The summary
    ///     still counts all of them.
    ///   - includesDefaultsValues: Whether UserDefaults values may appear; key names always do.
    public init(
        diff: AppSnapshotDiff,
        snapshotId: String,
        againstSnapshotId: String?,
        againstLiveUdid: String?,
        limit: Int,
        includesDefaultsValues: Bool,
        valuesFlag: String
    ) {
        self.snapshotId = snapshotId
        self.againstSnapshotId = againstSnapshotId
        self.againstLiveUdid = againstLiveUdid
        comparedContents = diff.comparedContents.identifier
        hasChanges = diff.hasChanges

        let fileChanges = diff.containerDiffs.flatMap(\.fileChanges)
        summary = Summary(filesAdded: fileChanges.count { $0.kind == .added },
                          filesRemoved: fileChanges.count { $0.kind == .removed },
                          filesModified: fileChanges.count { $0.kind == .modified },
                          userDefaultsChanges: diff.containerDiffs.reduce(0) { $0 + $1.defaultsChanges.count })

        var remaining = max(limit, 0)
        var containers: [ContainerDiff] = []

        for containerDiff in diff.containerDiffs where containerDiff.hasChanges {
            let files = containerDiff.fileChanges
                .sorted { $0.relativePath < $1.relativePath }
                .prefix(remaining)
                .map { FileChange(change: $0.kind.rawValue, path: $0.relativePath, oldByteSize: $0.oldByteSize, newByteSize: $0.newByteSize) }
            remaining -= files.count

            let defaults = containerDiff.defaultsChanges.map { change in
                DefaultsChange(change: change.kind.rawValue,
                               domain: change.domain,
                               key: change.key,
                               oldValue: includesDefaultsValues ? change.oldValue : nil,
                               newValue: includesDefaultsValues ? change.newValue : nil)
            }

            containers.append(ContainerDiff(container: containerDiff.kind.identifier, files: Array(files), userDefaults: defaults))
        }

        self.containers = containers
        truncated = containers.reduce(0) { $0 + $1.files.count } < fileChanges.count
        userDefaultsValuesNote = includesDefaultsValues || summary.userDefaultsChanges == 0
            ? nil
            : "UserDefaults values were left out; only key names are listed. Start the server with \(valuesFlag) to include them."
    }
}

// MARK: - Stable identifiers

extension SnapshotContainerKind {
    var identifier: String {
        switch self {
        case .appData:
            "appData"
        case let .appGroup(identifier):
            identifier
        }
    }
}

extension SnapshotContents {
    /// The names `capture_snapshot` takes and results report.
    static let identifiers = ["everything", "databases", "userDefaults", "databasesAndUserDefaults"]

    var identifier: String {
        switch (self, includes(.databases), includes(.userDefaults)) {
        case (.everything, _, _):
            "everything"
        case (_, true, true):
            "databasesAndUserDefaults"
        case (_, true, false):
            "databases"
        case (_, false, true):
            "userDefaults"
        case (_, false, false):
            "nothing"
        }
    }

    init?(identifier: String) {
        switch identifier {
        case "everything":
            self = .everything
        case "databases":
            self = .databases
        case "userDefaults":
            self = .userDefaults
        case "databasesAndUserDefaults":
            self = .databasesAndUserDefaults
        default:
            return nil
        }
    }
}
