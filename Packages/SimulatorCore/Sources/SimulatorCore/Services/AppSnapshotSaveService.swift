//
//  AppSnapshotSaveService.swift
//  SimulatorCore
//
//  Created by Nicolas Hiller on 20.10.26.
//

import Foundation
import os

/// Why a snapshot could not be saved to a folder.
public enum AppSnapshotSaveError: LocalizedError, Equatable {
    case destinationMissing(path: String)
    case destinationNotWritable(path: String)

    public var errorDescription: String? {
        switch self {
        case let .destinationMissing(path):
            "The folder \(path) does not exist."
        case let .destinationNotWritable(path):
            "The folder \(path) cannot be written to."
        }
    }
}

/// Saves an app's container state as a plainly named folder the user can see and hand around.
///
/// The public face of the snapshot layer for the app: the rest of it stays internal to the package
/// until a consumer needs it.
public protocol AppSnapshotSaving: AnyObject, Sendable {
    /// Captures `target` and moves the result into `directoryURL`, named by
    /// ``SnapshotExportNaming``.
    /// - Parameter progress: The fraction of the capture completed, from 0 to 1. Called off the
    ///   main actor.
    /// - Returns: The saved snapshot folder.
    /// - Throws: ``AppSnapshotSaveError`` before anything is captured when `directoryURL` cannot be
    ///   used, or whatever the capture or move failed with.
    func saveSnapshot(
        of target: AppSnapshotTarget,
        into directoryURL: URL,
        includeCaches: Bool,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> URL
}

/// Captures into the internal store and then *moves* the snapshot out of it, rather than copying.
///
/// The internal store has no listing or delete in the app yet (#90), so a copy left behind would be
/// disk use the user can neither see nor reclaim — in an app whose other headline feature is
/// reclaiming disk space. Within a volume the move is a rename, so the payload is written once.
/// The folder keeps the store's layout, manifest included, so it stays a complete snapshot.
public final class AppSnapshotSaveService: AppSnapshotSaving {
    private let snapshotService: AppSnapshotting
    private let timeZone: TimeZone
    private let now: @Sendable () -> Date

    public convenience init() {
        self.init(snapshotService: AppSnapshotService())
    }

    init(
        snapshotService: AppSnapshotting,
        timeZone: TimeZone = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.snapshotService = snapshotService
        self.timeZone = timeZone
        self.now = now
    }

    public func saveSnapshot(
        of target: AppSnapshotTarget,
        into directoryURL: URL,
        includeCaches: Bool,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> URL {
        // Checked before capturing: finding out the folder is gone after copying a large container
        // would waste the copy, and would leave the user waiting for an error.
        try Self.validateDestination(directoryURL)

        // Named for when the user asked, not when the copy finished, and used as the label too, so
        // the manifest inside the folder says the same thing as the folder's name.
        let folderName = SnapshotExportNaming.folderName(deviceName: target.deviceName,
                                                         osVersion: target.osVersion,
                                                         appName: target.appDisplayName,
                                                         date: now(),
                                                         timeZone: timeZone)
        let snapshot = try await snapshotService.captureSnapshot(of: target,
                                                                 label: folderName,
                                                                 includeCaches: includeCaches) { snapshotProgress in
            progress?(snapshotProgress.fractionCompleted)
        }

        do {
            return try await snapshotService.moveSnapshot(snapshot, into: directoryURL, folderName: folderName)
        } catch {
            // Nothing in the app lists the internal store yet, so a snapshot left there is
            // invisible disk use.
            os_log("Failed to move snapshot %{public}@ to %{public}@: %{public}@",
                   snapshot.id,
                   directoryURL.path,
                   error.localizedDescription)
            try? await snapshotService.deleteSnapshot(snapshot)

            throw error
        }
    }
}

private extension AppSnapshotSaveService {
    static func validateDestination(_ directoryURL: URL) throws {
        let path = directoryURL.path

        guard FileManager.default.directoryExistsAtURL(directoryURL) else {
            throw AppSnapshotSaveError.destinationMissing(path: path)
        }
        guard FileManager.default.isWritableFile(atPath: path) else {
            throw AppSnapshotSaveError.destinationNotWritable(path: path)
        }
    }
}
