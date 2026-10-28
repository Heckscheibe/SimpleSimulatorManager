//
//  RecentApps.swift
//  SimulatorCore
//

import Foundation

/// The rules behind the recent-apps list, shared by every consumer so they all agree on it.
public enum RecentApps {
    /// Maximum number of recent installed apps to keep.
    public static let maxCount = 20

    /// The recent-apps list derived from a full device load: most recent first, one entry per app
    /// and device (keeping the most recent), then capped at `limit`. Deduplicating before the cap
    /// keeps the list full whenever enough distinct apps exist.
    ///
    /// UI test runners are dropped *before* the cap when `hidingTestRunners` is set: filtering the
    /// capped list afterwards would leave the runners holding slots a real app should have had.
    public static func initial(
        from appChanges: [AppChange],
        limit: Int = maxCount,
        hidingTestRunners: Bool = false
    ) -> [AppChange] {
        let candidates = hidingTestRunners ? appChanges.filter { !$0.app.isTestRunner } : appChanges
        let sortedChanges = candidates.sorted { $0.timestamp > $1.timestamp }

        return Array(removingDuplicates(from: sortedChanges).prefix(limit))
    }

    /// What `DeviceManager` keeps so the list can be rebuilt either way without a reload: the
    /// `limit` most recent entries of each kind. Whichever way test runners are shown, the visible
    /// top `limit` is a subset of this, so toggling never has to rescan the disk.
    static func retained(from sortedChanges: [AppChange], limit: Int = maxCount) -> [AppChange] {
        let regular = sortedChanges.filter { !$0.app.isTestRunner }.prefix(limit)
        let runners = sortedChanges.filter { $0.app.isTestRunner }.prefix(limit)

        return (Array(regular) + Array(runners)).sorted { $0.timestamp > $1.timestamp }
    }

    /// The list consumers see: `retained` entries, with test runners dropped first when hidden,
    /// then capped.
    static func visible(from retainedChanges: [AppChange], hidingTestRunners: Bool, limit: Int = maxCount) -> [AppChange] {
        let candidates = hidingTestRunners ? retainedChanges.filter { !$0.app.isTestRunner } : retainedChanges

        return Array(candidates.prefix(limit))
    }

    /// Identifies an app on a specific device; an app installed on two devices is two entries.
    static func key(for change: AppChange) -> String {
        "\(change.app.bundleIdentifier)-\(change.device.udid)"
    }

    private static func removingDuplicates(from changes: [AppChange]) -> [AppChange] {
        var seen: Set<String> = []

        return changes.filter { seen.insert(key(for: $0)).inserted }
    }
}
