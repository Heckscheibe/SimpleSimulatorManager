//
//  MenuSearchViewModel.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 04.09.26.
//

import Combine
import Foundation
import Observation
import SimulatorCore

/// The panel's search state: the query, and the ranked hits for it.
///
/// The index follows the same publishers the menu itself is built from, but rebuilding it is not
/// free, and those publishers fire at launch, on every reload and on every FSEvents-driven device
/// refresh — almost always while nobody is searching. So a change only marks the index stale, and
/// it is rebuilt lazily: on the next query, or once per burst of changes while a query is live.
/// Never per keystroke, and never by rescanning the filesystem.
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
    @ObservationIgnored private var hidesTestRunnerApps = false
    /// Starts out stale, so the first query builds the index even if nothing was ever published —
    /// the device manager loads in the background and may not have emitted yet.
    @ObservationIgnored private var isIndexStale = true
    @ObservationIgnored private var isLiveRefreshScheduled = false

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
                self?.indexInputsChanged()
            }
            .store(in: &cancellables)

        deviceManager.recentInstalledApps
            .receive(on: DispatchQueue.main)
            .sink { [weak self] recentApps in
                self?.recentApps = recentApps
                self?.indexInputsChanged()
            }
            .store(in: &cancellables)

        settings.$visiblePlatforms
            .receive(on: DispatchQueue.main)
            .sink { [weak self] visiblePlatforms in
                self?.visiblePlatforms = visiblePlatforms
                self?.indexInputsChanged()
            }
            .store(in: &cancellables)

        settings.$hideTestRunnerApps
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hidesTestRunnerApps in
                self?.hidesTestRunnerApps = hidesTestRunnerApps
                self?.indexInputsChanged()
            }
            .store(in: &cancellables)
    }

    /// Marks the index stale. With no query that is all a change costs; with a live query the
    /// visible results are refreshed on the next main-queue turn, so the emissions of one reload
    /// (devices, then recent apps) share a single rebuild.
    func indexInputsChanged() {
        isIndexStale = true

        guard hasQuery, !isLiveRefreshScheduled else {
            return
        }

        isLiveRefreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            isLiveRefreshScheduled = false
            // An app installed while the panel is open with a live query has to show up in the
            // results, not just in the index.
            if hasQuery {
                refreshResults()
            }
        }
    }

    /// Synchronous on purpose: `MenuPanelView.queryChanged` reads `results` straight after the
    /// query changes, so a stale index has to be rebuilt here rather than on a later turn.
    func refreshResults() {
        if hasQuery, isIndexStale {
            rebuildIndex()
        }

        results = searchService.results(for: query)
    }

    func rebuildIndex() {
        searchService.updateIndex(devices: devices,
                                  recentApps: recentApps,
                                  visiblePlatforms: visiblePlatforms,
                                  hidesTestRunnerApps: hidesTestRunnerApps)
        isIndexStale = false
    }
}
