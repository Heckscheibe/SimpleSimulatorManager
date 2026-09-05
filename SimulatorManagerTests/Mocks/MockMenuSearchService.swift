//
//  MockMenuSearchService.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 04.09.26.
//

import Foundation
@testable import SimulatorManager

/// Lets a test drive what search returns without depending on the real matching, so the panel's
/// behaviour and the ranking rules are covered separately.
final class MockMenuSearchService: MenuSearching {
    private(set) var indexUpdateCount = 0
    private(set) var lastDevices: [Device] = []
    private(set) var lastRecentApps: [AppChange] = []
    private(set) var lastVisiblePlatforms: Set<SimulatorPlatform> = []
    private(set) var queries: [String] = []

    /// Returned for any non-empty query.
    var stubbedResults: [MenuSearchResult] = []

    func updateIndex(
        devices: [Device],
        recentApps: [AppChange],
        visiblePlatforms: Set<SimulatorPlatform>
    ) {
        indexUpdateCount += 1
        lastDevices = devices
        lastRecentApps = recentApps
        lastVisiblePlatforms = visiblePlatforms
    }

    func results(for query: String) -> [MenuSearchResult] {
        queries.append(query)

        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        return stubbedResults
    }
}
