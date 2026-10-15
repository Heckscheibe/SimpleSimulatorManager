//
//  RecentApps.swift
//  SimulatorCore
//

import Foundation

/// The rules behind the recent-apps list, shared by every consumer so they all agree on it.
public enum RecentApps {
    /// Maximum number of recent installed apps to keep.
    public static let maxCount = 20

    /// The recent-apps list derived from a full device load: most recent first, capped at `limit`,
    /// then one entry per app and device, keeping the most recent.
    public static func initial(from appChanges: [AppChange], limit: Int = maxCount) -> [AppChange] {
        let sortedChanges = appChanges.sorted { $0.timestamp > $1.timestamp }
        let limitedChanges = Array(sortedChanges.prefix(limit))

        return removingDuplicates(from: limitedChanges)
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
