//
//  SimulatorQueryService+Snapshots.swift
//  SimulatorMCPServer
//

import Foundation
import os
import SimulatorCore

/// What `capture_snapshot` was asked for, already validated.
public struct SnapshotCaptureRequest: Sendable, Equatable {
    public let bundleIdentifier: String
    public let udid: String
    public let label: String?
    public let contents: SnapshotContents
    public let includeCaches: Bool
    public let terminateApp: Bool

    public init(
        bundleIdentifier: String,
        udid: String,
        label: String? = nil,
        contents: SnapshotContents = .everything,
        includeCaches: Bool = false,
        terminateApp: Bool = true
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.udid = udid
        self.label = label
        self.contents = contents
        self.includeCaches = includeCaches
        self.terminateApp = terminateApp
    }
}

/// What `diff_snapshot` compares a snapshot with.
public enum SnapshotDiffSubject: Sendable, Equatable {
    case snapshot(id: String)
    /// The app as installed now; `udid` `nil` means the snapshot's own device.
    case live(udid: String?)
}

public struct SnapshotDiffRequest: Sendable, Equatable {
    public let snapshotId: String
    public let against: SnapshotDiffSubject
    public let limit: Int
    public let includesDefaultsValues: Bool

    public init(snapshotId: String, against: SnapshotDiffSubject, limit: Int, includesDefaultsValues: Bool) {
        self.snapshotId = snapshotId
        self.against = against
        self.limit = limit
        self.includesDefaultsValues = includesDefaultsValues
    }
}

public extension SimulatorQueryService {
    func snapshots(ofBundleIdentifier bundleIdentifier: String?) async -> [SnapshotDTO] {
        let snapshots =
            if let bundleIdentifier {
                await snapshotService.snapshots(forBundleIdentifier: bundleIdentifier)
            } else {
                await snapshotService.allSnapshots()
            }

        return snapshots.map(SnapshotDTO.init(snapshot:))
    }

    func captureSnapshot(_ request: SnapshotCaptureRequest) async throws -> SnapshotCaptureDTO {
        let target = try await target(bundleIdentifier: request.bundleIdentifier, udid: request.udid)
        // The same name Save Snapshot to Folder gives a snapshot, so the two read alike in a listing.
        let label = request.label ?? SnapshotExportNaming.folderName(deviceName: target.deviceName,
                                                                     osVersion: target.osVersion,
                                                                     appName: target.appDisplayName,
                                                                     date: Date()) + request.contents.labelSuffix
        let capture = try await snapshotService.captureSnapshot(of: target,
                                                                label: label,
                                                                contents: request.contents,
                                                                includeCaches: request.includeCaches,
                                                                terminatingApp: request.terminateApp,
                                                                progress: nil)
        os_log("MCP server captured snapshot %{public}@ of %{public}@", capture.snapshot.id, request.bundleIdentifier)

        return SnapshotCaptureDTO(capture: capture)
    }

    func diffSnapshot(_ request: SnapshotDiffRequest) async throws -> SnapshotDiffDTO {
        let snapshot = try await snapshot(withId: request.snapshotId)
        let diff: AppSnapshotDiff
        var againstSnapshotId: String?
        var againstLiveUdid: String?

        switch request.against {
        case let .snapshot(id):
            diff = try await snapshotService.diff(snapshot, against: self.snapshot(withId: id))
            againstSnapshotId = id
        case let .live(udid):
            let target = try await target(bundleIdentifier: snapshot.manifest.bundleIdentifier,
                                          udid: udid ?? snapshot.manifest.deviceUDID)
            diff = try await snapshotService.diff(snapshot, againstLiveContainersOf: target)
            againstLiveUdid = target.deviceUDID
        }

        return SnapshotDiffDTO(diff: diff,
                               snapshotId: snapshot.id,
                               againstSnapshotId: againstSnapshotId,
                               againstLiveUdid: againstLiveUdid,
                               limit: request.limit,
                               includesDefaultsValues: request.includesDefaultsValues,
                               valuesFlag: ServerOptions.allowUserDefaultsFlag)
    }

    func restoreSnapshot(withId id: String, ontoDeviceWithUdid udid: String?, acceptingWarnings: Bool) async throws -> SnapshotRestoreDTO {
        let snapshot = try await snapshot(withId: id)
        let target = try await target(bundleIdentifier: snapshot.manifest.bundleIdentifier,
                                      udid: udid ?? snapshot.manifest.deviceUDID)
        let plan = try await snapshotService.prepareRestore(of: snapshot, to: target)
        let warnings = plan.warnings.map(\.message)

        // Nothing is written until the agent has seen the warnings and said they are expected —
        // for migration testing they usually are: an old build's data onto the new build.
        guard !plan.hasWarnings || acceptingWarnings else {
            return SnapshotRestoreDTO(
                restored: false,
                snapshot: SnapshotDTO(snapshot: snapshot),
                udid: target.deviceUDID,
                warnings: warnings,
                safetySnapshotId: nil,
                message: "Nothing was restored. The snapshot differs from the installed app as listed in warnings. "
                    + "A different app version is expected when testing a migration from an older build; an app group "
                    + "only one side has means that group is skipped or keeps its current data. "
                    + "Call again with accept_warnings: true to restore anyway."
            )
        }

        let restore = try await snapshotService.restore(plan, progress: nil)
        os_log("MCP server restored snapshot %{public}@ onto %{public}@", id, target.deviceUDID)

        var restoreWarnings = warnings
        let message: String

        switch restore.termination {
        case .terminated:
            message = "Restored. The app was terminated first. Restore safetySnapshotId to undo."
        case .notRunning, .notRequested:
            message = "Restored. The app was not running. Restore safetySnapshotId to undo."
        case let .failed(reason):
            message = "Restored, but the app could not be terminated first. Restore safetySnapshotId to undo."
            restoreWarnings.append("The app could not be terminated (\(reason)). If it is still running it can write its "
                + "old state back over the restored files; terminate it and restore again.")
        }

        return SnapshotRestoreDTO(
            restored: true,
            snapshot: SnapshotDTO(snapshot: snapshot),
            udid: target.deviceUDID,
            warnings: restoreWarnings,
            safetySnapshotId: restore.safetySnapshot.id,
            appTermination: restore.termination.identifier,
            message: message
        )
    }

    func deleteSnapshot(withId id: String) async throws -> SnapshotDTO {
        let snapshot = try await snapshot(withId: id)
        try await snapshotService.deleteSnapshot(snapshot)

        return SnapshotDTO(snapshot: snapshot)
    }
}

private extension SimulatorQueryService {
    func snapshot(withId id: String) async throws -> AppSnapshot {
        guard let snapshot = await snapshotService.snapshot(withID: id) else {
            throw SimulatorQueryError.unknownSnapshot(id: id)
        }

        return snapshot
    }

    /// Resolved from what discovery found, so no container path is derived a second time and no
    /// caller ever supplies one.
    func target(bundleIdentifier: String, udid: String) async throws -> AppSnapshotTarget {
        try await Self.workQueue.perform { [self] in
            let device = try loadDevice(withUdid: udid)
            let app = try Self.app(withBundleIdentifier: bundleIdentifier, on: device)

            guard let target = AppSnapshotTarget(app: app, device: device) else {
                throw SimulatorQueryError.appHasNoDataContainer(bundleIdentifier: bundleIdentifier, udid: device.udid)
            }

            return target
        }
    }
}
