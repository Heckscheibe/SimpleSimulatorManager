//
//  MenuSearchViewModel.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 04.09.26.
//

import Combine
import Foundation
import Observation

/// The panel's search state: the query, and the ranked hits for it.
///
/// The index follows the same publishers the menu itself is built from, so it is rebuilt when
/// devices, recent apps or platform visibility change — never per keystroke, and never by
/// rescanning the filesystem.
@MainActor
@Observable
final class MenuSearchViewModel {
    var query: String = "" {
        didSet {
            guard query != oldValue else {
                return
            }

            refreshResults()
        }
    }

    private(set) var results: [MenuSearchResult] = []

    @ObservationIgnored private let searchService: any MenuSearching
    @ObservationIgnored private var cancellables: Set<AnyCancellable> = []
    @ObservationIgnored private var devices: [Device] = []
    @ObservationIgnored private var recentApps: [AppChange] = []
    @ObservationIgnored private var visiblePlatforms: Set<SimulatorPlatform> = []

    init(
        deviceManager: DeviceManaging,
        settings: Settings,
        searchService: any MenuSearching = MenuSearchService()
    ) {
        self.searchService = searchService

        bind(to: deviceManager, settings: settings)
    }

    /// Whether the panel should show results rather than the browsable menu. A whitespace-only
    /// query is not a search: showing everything is the browsable menu's job.
    var hasQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func clear() {
        query = ""
    }

    /// What <kbd>esc</kbd> should do next.
    enum CancelOutcome: Equatable {
        case clearedQuery
        case shouldDismiss
    }

    /// Escape clears the query first and closes the panel only once there is nothing left to
    /// clear, so a mistyped search never costs the whole panel.
    func cancel() -> CancelOutcome {
        guard hasQuery else {
            return .shouldDismiss
        }

        clear()

        return .clearedQuery
    }
}

private extension MenuSearchViewModel {
    func bind(to deviceManager: DeviceManaging, settings: Settings) {
        deviceManager.devices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                self?.devices = devices
                self?.rebuildIndex()
            }
            .store(in: &cancellables)

        deviceManager.recentInstalledApps
            .receive(on: DispatchQueue.main)
            .sink { [weak self] recentApps in
                self?.recentApps = recentApps
                self?.rebuildIndex()
            }
            .store(in: &cancellables)

        settings.$visiblePlatforms
            .receive(on: DispatchQueue.main)
            .sink { [weak self] visiblePlatforms in
                self?.visiblePlatforms = visiblePlatforms
                self?.rebuildIndex()
            }
            .store(in: &cancellables)
    }

    func rebuildIndex() {
        searchService.updateIndex(devices: devices,
                                  recentApps: recentApps,
                                  visiblePlatforms: visiblePlatforms)
        // An app installed while the panel is open with a live query has to show up in the results,
        // not just in the index.
        refreshResults()
    }

    func refreshResults() {
        results = searchService.results(for: query)
    }
}
