//
//  AppSnapshotService.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 05.09.26.
//

import Foundation
import os

/// Capturing, restoring and comparing an app's container state.
///
/// The missing primitive this fills is resetting *one* app: `simctl erase` wipes the whole device
/// and forces every app to be reinstalled, which is far too blunt for putting a single app back the
/// way it was ten minutes ago.
protocol AppSnapshotting: AnyObject, Sendable {
    func snapshots(forBundleIdentifier bundleIdentifier: String) async -> [AppSnapshot]
    func allSnapshots() async -> [AppSnapshot]
    func totalSnapshotByteSize() async -> Int64
    func deleteSnapshot(_ snapshot: AppSnapshot) async throws

    func captureSnapshot(
        of target: AppSnapshotTarget,
        label: String,
        includeCaches: Bool,
        progress: (@Sendable (SnapshotProgress) -> Void)?
    ) async throws -> AppSnapshot

    /// Validates a restore without performing it, so a restore that was never going to be legal
    /// fails before anything is overwritten.
    /// - Returns: The plan, carrying any mismatches for the caller to confirm.
    /// - Throws: When the snapshot cannot be restored onto this target at all.
    func prepareRestore(of snapshot: AppSnapshot, to target: AppSnapshotTarget) async throws -> SnapshotRestorePlan

    /// - Returns: The safety snapshot taken of the live container before it was overwritten.
    func restore(
        _ plan: SnapshotRestorePlan,
        progress: (@Sendable (SnapshotProgress) -> Void)?
    ) async throws -> AppSnapshot

    func diff(_ snapshot: AppSnapshot, against other: AppSnapshot) async throws -> AppSnapshotDiff
    func diff(_ snapshot: AppSnapshot, againstLiveContainersOf target: AppSnapshotTarget) async throws -> AppSnapshotDiff
}

extension AppSnapshotting {
    func captureSnapshot(of target: AppSnapshotTarget, label: String, includeCaches: Bool) async throws -> AppSnapshot {
        try await captureSnapshot(of: target, label: label, includeCaches: includeCaches, progress: nil)
    }

    func restore(_ plan: SnapshotRestorePlan) async throws -> AppSnapshot {
        try await restore(plan, progress: nil)
    }
}

final class AppSnapshotService: AppSnapshotting {
    static let safetySnapshotLabelPrefix = "Before restoring"

    /// Copying and hashing a container are blocking work, and `Task.detached` shares the Swift
    /// concurrency cooperative pool — a multi-second directory walk there occupies a cooperative
    /// thread with no suspension point and starves unrelated async work. Hop to a dedicated queue
    /// instead, as ``SimulatorCleanupService`` and ``DeviceManager`` do. Concurrent, so two
    /// containers of one snapshot are not serialised behind each other.
    private static let workQueue = DispatchQueue(
        label: "AppSnapshotService.workQueue",
        qos: .userInitiated,
        attributes: .concurrent
    )

    private let store: AppSnapshotStoring
    private let appActionService: SimulatorAppActionServing

    init(
        store: AppSnapshotStoring = AppSnapshotStore(),
        appActionService: SimulatorAppActionServing = SimulatorAppActionService()
    ) {
        self.store = store
        self.appActionService = appActionService
    }

    // MARK: - Listing

    func snapshots(forBundleIdentifier bundleIdentifier: String) async -> [AppSnapshot] {
        let store = store

        return (try? await onWorkQueue { store.snapshots(forBundleIdentifier: bundleIdentifier) }) ?? []
    }

    func allSnapshots() async -> [AppSnapshot] {
        let store = store

        return (try? await onWorkQueue { store.allSnapshots() }) ?? []
    }

    func totalSnapshotByteSize() async -> Int64 {
        let store = store

        return (try? await onWorkQueue { store.totalByteSize() }) ?? 0
    }

    func deleteSnapshot(_ snapshot: AppSnapshot) async throws {
        let store = store

        try await onWorkQueue { try store.delete(snapshot) }
        os_log("Deleted snapshot %{public}@ of %{public}@", snapshot.id, snapshot.manifest.bundleIdentifier)
    }

    // MARK: - Capture

    func captureSnapshot(
        of target: AppSnapshotTarget,
        label: String,
        includeCaches: Bool,
        progress: (@Sendable (SnapshotProgress) -> Void)?
    ) async throws -> AppSnapshot {
        try await capture(target,
                          label: label,
                          includeCaches: includeCaches,
                          isSafetySnapshot: false,
                          progress: progress)
    }

    // MARK: - Restore

    func prepareRestore(of snapshot: AppSnapshot, to target: AppSnapshotTarget) async throws -> SnapshotRestorePlan {
        let manifest = snapshot.manifest

        // Restoring across bundle identifiers is not a mismatch to warn about; the containers hold
        // different apps' state and nothing sensible comes of mixing them.
        guard manifest.bundleIdentifier == target.bundleIdentifier else {
            throw AppSnapshotError.bundleIdentifierMismatch(snapshot: manifest.bundleIdentifier,
                                                            target: target.bundleIdentifier)
        }

        // Every payload is checked before a single byte is written. A restore that fails halfway
        // leaves a container that is neither the old state nor the new one.
        try await onWorkQueue {
            for container in manifest.containers {
                guard FileManager.default.directoryExistsAtURL(snapshot.payloadURL(for: container)) else {
                    throw AppSnapshotError.missingPayload(containerName: container.kind.displayName)
                }
            }
        }

        return SnapshotRestorePlan(snapshot: snapshot,
                                   target: target,
                                   warnings: Self.warnings(restoring: manifest, onto: target))
    }

    func restore(
        _ plan: SnapshotRestorePlan,
        progress: (@Sendable (SnapshotProgress) -> Void)?
    ) async throws -> AppSnapshot {
        let target = plan.target
        let manifest = plan.snapshot.manifest

        // Restoring underneath a running app leaves it holding stale, possibly WAL-inconsistent
        // state, and it may write its in-memory copy back over the restored files on exit.
        do {
            try await appActionService.terminateApp(bundleIdentifier: target.bundleIdentifier,
                                                    deviceUdid: target.deviceUDID)
        } catch {
            // Reported rather than fatal: refusing to restore because the app could not be stopped
            // would block the common case where the device is not even booted.
            os_log("Could not terminate %{public}@ before restoring: %{public}@",
                   target.bundleIdentifier,
                   error.localizedDescription)
        }

        // Taken after the terminate, so the undo point is the same settled state the restore
        // overwrites rather than one captured from under a live app.
        let safetySnapshot = try await capture(
            target,
            label: "\(Self.safetySnapshotLabelPrefix) \(Self.describe(manifest))",
            includeCaches: manifest.includesCaches,
            isSafetySnapshot: true,
            progress: nil
        )

        let containersByKind = Self.destinationURLsByKind(for: target)
        var copiedByteCount: Int64 = 0

        for container in manifest.containers {
            guard let destinationURL = containersByKind[container.kind] else {
                // Reported as a warning by `prepareRestore` and skipped here: recreating an app
                // group container the simulator no longer knows about would not register it.
                os_log("Skipping %{public}@ during restore; it is not present on the target",
                       container.kind.displayName)

                continue
            }

            let payloadURL = plan.snapshot.payloadURL(for: container)
            let preserved = Self.preservedRelativePaths(includesCaches: manifest.includesCaches)

            try await onWorkQueue {
                try SnapshotContainerFiles.replaceContents(of: destinationURL,
                                                           withContentsOf: payloadURL,
                                                           preservedRelativePaths: preserved)
            }

            copiedByteCount += container.byteSize
            progress?(SnapshotProgress(copiedByteCount: copiedByteCount,
                                       totalByteCount: manifest.totalByteSize,
                                       currentRelativePath: container.kind.displayName))
        }

        os_log("Restored snapshot %{public}@ onto %{public}@ (%{public}@)",
               plan.snapshot.id,
               target.bundleIdentifier,
               target.deviceUDID)

        return safetySnapshot
    }

    // MARK: - Diff

    func diff(_ snapshot: AppSnapshot, against other: AppSnapshot) async throws -> AppSnapshotDiff {
        let oldContainers = Self.payloadURLsByKind(of: snapshot)
        let newContainers = Self.payloadURLsByKind(of: other)
        // A payload only ever holds what its snapshot captured, so no exclusion applies on either
        // side; the snapshots decide what is comparable, not this call.
        let diffs = try await containerDiffs(oldContainers: oldContainers,
                                             newContainers: newContainers,
                                             includeCaches: true)

        return AppSnapshotDiff(oldDescription: Self.describe(snapshot.manifest),
                               newDescription: Self.describe(other.manifest),
                               containerDiffs: diffs)
    }

    func diff(_ snapshot: AppSnapshot, againstLiveContainersOf target: AppSnapshotTarget) async throws -> AppSnapshotDiff {
        let oldContainers = Self.payloadURLsByKind(of: snapshot)
        let newContainers = Self.destinationURLsByKind(for: target)
        // The live container still holds whatever the snapshot left out, so the same exclusion is
        // applied to it. Otherwise every cache file the app has written since would be reported as
        // added, drowning the changes that mean something.
        let diffs = try await containerDiffs(oldContainers: oldContainers,
                                             newContainers: newContainers,
                                             includeCaches: snapshot.manifest.includesCaches)

        return AppSnapshotDiff(oldDescription: Self.describe(snapshot.manifest),
                               newDescription: "\(target.appDisplayName) on \(target.deviceName), as installed",
                               containerDiffs: diffs)
    }
}

// MARK: - Capture

private extension AppSnapshotService {
    func capture(
        _ target: AppSnapshotTarget,
        label: String,
        includeCaches: Bool,
        isSafetySnapshot: Bool,
        progress: (@Sendable (SnapshotProgress) -> Void)?
    ) async throws -> AppSnapshot {
        let identifier = UUID().uuidString
        let store = store
        let directoryURL = try await onWorkQueue {
            try store.makeSnapshotDirectory(bundleIdentifier: target.bundleIdentifier, id: identifier)
        }

        do {
            let containers = try await onWorkQueue {
                try Self.captureContainers(of: target,
                                           into: directoryURL,
                                           includeCaches: includeCaches,
                                           progress: progress)
            }

            guard !containers.isEmpty else {
                throw AppSnapshotError.nothingToCapture
            }

            let manifest = AppSnapshotManifest(
                id: identifier,
                label: label,
                bundleIdentifier: target.bundleIdentifier,
                appDisplayName: target.appDisplayName,
                appShortVersion: target.appShortVersion,
                appBuildVersion: target.appBuildVersion,
                deviceUDID: target.deviceUDID,
                deviceName: target.deviceName,
                osVersion: target.osVersion,
                createdAt: AppSnapshotManifest.persistableTimestamp(),
                includesCaches: includeCaches,
                totalByteSize: containers.reduce(0) { $0 + $1.byteSize },
                containers: containers,
                isSafetySnapshot: isSafetySnapshot
            )

            try await onWorkQueue { try store.write(manifest, to: directoryURL) }
            os_log("Captured snapshot %{public}@ of %{public}@ (%{public}ld bytes)",
                   identifier,
                   target.bundleIdentifier,
                   manifest.totalByteSize)

            return AppSnapshot(manifest: manifest, directoryURL: directoryURL)
        } catch {
            // A payload with no manifest is unlistable and unrestorable, so a failed capture takes
            // its own directory with it rather than leaving dead bytes in Application Support.
            store.discardSnapshotDirectory(at: directoryURL)

            throw error
        }
    }

    static func captureContainers(
        of target: AppSnapshotTarget,
        into directoryURL: URL,
        includeCaches: Bool,
        progress: (@Sendable (SnapshotProgress) -> Void)?
    ) throws -> [CapturedContainer] {
        let containersDirectoryURL = directoryURL
            .appendingPathComponent(AppSnapshotManifest.containersDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: containersDirectoryURL, withIntermediateDirectories: true)

        var sources: [(kind: SnapshotContainerKind, url: URL, payloadDirectoryName: String)] = []

        if FileManager.default.directoryExistsAtURL(target.dataContainerURL) {
            sources.append((.appData,
                            target.dataContainerURL,
                            AppSnapshotManifest.appDataPayloadDirectoryName))
        }

        for (index, group) in target.appGroupContainers.enumerated()
            where FileManager.default.directoryExistsAtURL(group.url) {
            sources.append((.appGroup(identifier: group.identifier), group.url, "app-group-\(index)"))
        }

        // Sizing up front costs one extra walk but is what makes progress a fraction rather than a
        // spinner, and a container large enough to need progress is large enough to warrant it.
        let totalByteCount = sources.reduce(Int64(0)) { total, source in
            total + SnapshotContainerFiles
                .fileSizesByRelativePath(in: source.url, includeCaches: includeCaches)
                .values
                .reduce(0, +)
        }

        return try sources.map { source in
            let byteSize = try SnapshotContainerFiles.copyContainer(
                at: source.url,
                to: containersDirectoryURL.appendingPathComponent(source.payloadDirectoryName, isDirectory: true),
                includeCaches: includeCaches,
                totalByteCount: totalByteCount,
                progress: progress
            )

            return CapturedContainer(kind: source.kind,
                                     payloadDirectoryName: source.payloadDirectoryName,
                                     byteSize: byteSize)
        }
    }
}

// MARK: - Restore support

private extension AppSnapshotService {
    static func warnings(restoring manifest: AppSnapshotManifest, onto target: AppSnapshotTarget) -> [SnapshotRestoreWarning] {
        var warnings: [SnapshotRestoreWarning] = []

        if manifest.appShortVersion != target.appShortVersion {
            warnings.append(.appShortVersionMismatch(snapshot: manifest.appShortVersion,
                                                     target: target.appShortVersion))
        }
        if manifest.appBuildVersion != target.appBuildVersion {
            warnings.append(.appBuildVersionMismatch(snapshot: manifest.appBuildVersion,
                                                     target: target.appBuildVersion))
        }
        if manifest.osVersion != target.osVersion {
            warnings.append(.osVersionMismatch(snapshot: manifest.osVersion, target: target.osVersion))
        }

        let available = Set(destinationURLsByKind(for: target).keys)
        warnings.append(contentsOf: manifest.containers
            .map(\.kind)
            .filter { !available.contains($0) }
            .map(SnapshotRestoreWarning.containerMissingOnTarget))

        return warnings
    }

    /// What a restore must not delete.
    ///
    /// The container metadata plist always, because it identifies the container rather than holding
    /// app state. `Library/Caches` and `tmp` only when the snapshot left them out: there is no
    /// payload to put back, and wiping regenerable data the user deliberately did not capture is
    /// destruction with nothing to show for it.
    static func preservedRelativePaths(includesCaches: Bool) -> Set<String> {
        var preserved: Set<String> = [SnapshotContainerFiles.containerMetadataFileName]

        if !includesCaches {
            preserved.formUnion([SimulatorPaths.cachesPath, SimulatorPaths.temporaryPath])
        }

        return preserved
    }

    static func destinationURLsByKind(for target: AppSnapshotTarget) -> [SnapshotContainerKind: URL] {
        var urlsByKind: [SnapshotContainerKind: URL] = [.appData: target.dataContainerURL]

        for group in target.appGroupContainers {
            urlsByKind[.appGroup(identifier: group.identifier)] = group.url
        }

        return urlsByKind
    }

    static func payloadURLsByKind(of snapshot: AppSnapshot) -> [SnapshotContainerKind: URL] {
        var urlsByKind: [SnapshotContainerKind: URL] = [:]

        for container in snapshot.manifest.containers {
            urlsByKind[container.kind] = snapshot.payloadURL(for: container)
        }

        return urlsByKind
    }

    static func describe(_ manifest: AppSnapshotManifest) -> String {
        let date = manifest.createdAt.formatted(date: .abbreviated, time: .shortened)

        return manifest.label.isEmpty ? date : "\(manifest.label) (\(date))"
    }

    func onWorkQueue<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            Self.workQueue.async {
                continuation.resume(with: Result { try work() })
            }
        }
    }
}

// MARK: - Diffing

private extension AppSnapshotService {
    func containerDiffs(
        oldContainers: [SnapshotContainerKind: URL],
        newContainers: [SnapshotContainerKind: URL],
        includeCaches: Bool
    ) async throws -> [SnapshotContainerDiff] {
        let kinds = Set(oldContainers.keys).union(newContainers.keys).sorted { $0.displayName < $1.displayName }

        return try await onWorkQueue {
            kinds.map { kind in
                SnapshotComparison.compare(oldContainerURL: oldContainers[kind],
                                           newContainerURL: newContainers[kind],
                                           kind: kind,
                                           includeCaches: includeCaches)
            }
        }
    }
}
