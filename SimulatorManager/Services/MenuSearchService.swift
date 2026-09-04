//
//  MenuSearchService.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 04.09.26.
//

import Foundation

// MARK: - Protocols

/// Matches a query against the simulators and apps the menu can show.
///
/// Behind a protocol, like ``DeviceManaging`` and ``DeviceAppMonitoring``, so the panel that
/// consumes it can be exercised against a mock.
protocol MenuSearching: AnyObject {
    /// Rebuilds the searchable index.
    ///
    /// Cheap enough to call whenever devices, recent apps or platform visibility change, and far
    /// too expensive to call per keystroke: every searchable string is normalised and tokenised
    /// here so that ``results(for:)`` only ever compares prepared strings.
    ///
    /// - Parameters:
    ///   - devices: The devices to index, with their apps already loaded.
    ///   - recentApps: The recent-apps list, used for ranking only. Entries whose device is not in
    ///     `devices`, or whose platform is hidden, do not add anything to the index.
    ///   - visiblePlatforms: Platforms the user has not hidden. A device on a hidden platform, and
    ///     every app installed on it, is left out entirely — search must never surface something
    ///     the browsable menu refuses to show.
    func updateIndex(
        devices: [Device],
        recentApps: [AppChange],
        visiblePlatforms: Set<SimulatorPlatform>
    )

    /// Ranked hits for `query`, best first.
    ///
    /// Returns an empty list for an empty or whitespace-only query: showing everything is the
    /// browsable menu's job, not search's.
    func results(for query: String) -> [MenuSearchResult]
}

// MARK: - Service

/// Matching runs on every keystroke, so this type does no filesystem access at all and no string
/// preparation outside ``updateIndex(devices:recentApps:visiblePlatforms:)``.
final class MenuSearchService: MenuSearching {
    private var entries: [MenuSearchIndexEntry] = []

    func updateIndex(
        devices: [Device],
        recentApps: [AppChange],
        visiblePlatforms: Set<SimulatorPlatform>
    ) {
        let recentRanks = Self.recentRanks(for: recentApps)

        entries = devices
            .filter { visiblePlatforms.contains($0.simulatorPlatform) }
            .flatMap { device in
                [Self.makeEntry(for: device)] + device.apps.map { app in
                    Self.makeEntry(for: app, on: device, recentRanks: recentRanks)
                }
            }
    }

    func results(for query: String) -> [MenuSearchResult] {
        let needle = MenuSearchText.normalized(query.trimmingCharacters(in: .whitespacesAndNewlines))

        guard !needle.isEmpty else {
            return []
        }

        return entries
            .compactMap { entry in
                entry.score(for: needle).map { ScoredEntry(entry: entry, score: $0) }
            }
            .sorted(by: Self.isOrderedBefore)
            .map { $0.entry.result }
    }
}

// MARK: - Ranking

private extension MenuSearchService {
    /// An entry paired with the best score any of its fields achieved for the current query.
    struct ScoredEntry {
        let entry: MenuSearchIndexEntry
        let score: MenuSearchScore
    }

    /// The ranking from the top down: recent apps, then match quality, then devices before apps,
    /// then alphabetically. The last key is unique, so the order is total — results never shuffle
    /// between keystrokes.
    static func isOrderedBefore(_ lhs: ScoredEntry, _ rhs: ScoredEntry) -> Bool {
        if lhs.entry.recentRank != rhs.entry.recentRank {
            return lhs.entry.recentRank < rhs.entry.recentRank
        }
        if lhs.score != rhs.score {
            return lhs.score < rhs.score
        }
        if lhs.entry.kindRank != rhs.entry.kindRank {
            return lhs.entry.kindRank < rhs.entry.kindRank
        }
        if lhs.entry.sortTitle != rhs.entry.sortTitle {
            return lhs.entry.sortTitle < rhs.entry.sortTitle
        }

        return lhs.entry.sortIdentifier < rhs.entry.sortIdentifier
    }

    /// Maps each recent app to its position in the recent list, most recent first. Keyed the same
    /// way `DeviceManager` dedupes recent apps: bundle identifier plus device UDID.
    static func recentRanks(for recentApps: [AppChange]) -> [String: Int] {
        let sortedChanges = recentApps.sorted { $0.timestamp > $1.timestamp }

        return sortedChanges.enumerated().reduce(into: [:]) { ranks, element in
            let key = MenuSearchResult.identifier(forAppWithBundleIdentifier: element.element.app.bundleIdentifier,
                                                  onDeviceWithUdid: element.element.device.udid)

            // The list can hold the same app twice for one device; the earlier entry is the more
            // recent one, so the first rank seen wins.
            if ranks[key] == nil {
                ranks[key] = element.offset
            }
        }
    }
}

// MARK: - Index construction

private extension MenuSearchService {
    static func makeEntry(for device: Device) -> MenuSearchIndexEntry {
        let combined = Self.combinedDeviceName(for: device)
        let result = MenuSearchResult(id: MenuSearchResult.identifier(forDeviceWithUdid: device.udid),
                                      kind: .device(device),
                                      title: device.name,
                                      subtitle: device.osVersion,
                                      iconName: device.simulatorPlatform.iconName)

        return MenuSearchIndexEntry(result: result,
                                    primaryFields: [MenuSearchField(device.name)],
                                    // The combined form is what makes "iPhone 16 Pro 18.2" match a
                                    // device whose name and OS version are stored separately.
                                    secondaryFields: [MenuSearchField(device.osVersion), MenuSearchField(combined)],
                                    recentRank: nil,
                                    kindRank: 0,
                                    sortTitle: MenuSearchText.normalized(device.name),
                                    sortIdentifier: result.id)
    }

    static func makeEntry(
        for app: any SimulatorApp,
        on device: Device,
        recentRanks: [String: Int]
    ) -> MenuSearchIndexEntry {
        let combined = Self.combinedDeviceName(for: device)
        let identifier = MenuSearchResult.identifier(forAppWithBundleIdentifier: app.bundleIdentifier,
                                                     onDeviceWithUdid: device.udid)
        let result = MenuSearchResult(id: identifier,
                                      kind: .app(app: app, device: device),
                                      title: app.displayName,
                                      subtitle: combined,
                                      iconName: app.iconName)

        return MenuSearchIndexEntry(result: result,
                                    primaryFields: [MenuSearchField(app.displayName)],
                                    secondaryFields: [
                                        MenuSearchField(app.bundleIdentifier),
                                        MenuSearchField(device.name),
                                        MenuSearchField(device.osVersion),
                                        MenuSearchField(combined)
                                    ],
                                    recentRank: recentRanks[identifier],
                                    kindRank: 1,
                                    sortTitle: MenuSearchText.normalized(app.displayName),
                                    sortIdentifier: identifier)
    }

    static func combinedDeviceName(for device: Device) -> String {
        "\(device.name) \(device.osVersion)"
    }
}
