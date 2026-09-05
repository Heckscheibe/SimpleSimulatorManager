//
//  MenuSearchViewModelTests.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 04.09.26.
//

import Foundation
import Testing
@testable import SimulatorManager

@Suite("MenuSearchViewModel Tests")
@MainActor
struct MenuSearchViewModelTests {
    @Test("An empty query yields no results, so the panel keeps browsing")
    func emptyQueryYieldsBrowseMode() {
        let context = Context()
        defer { context.tearDown() }

        context.searchService.stubbedResults = [context.appResult()]

        #expect(!context.viewModel.hasQuery)
        #expect(context.viewModel.results.isEmpty)
    }

    @Test("A whitespace-only query is not a search")
    func whitespaceOnlyQueryIsNotASearch() {
        let context = Context()
        defer { context.tearDown() }

        context.viewModel.query = "   "

        #expect(!context.viewModel.hasQuery)
        #expect(context.viewModel.results.isEmpty)
    }

    @Test("Typing produces results, and clearing the query takes them away again")
    func typingProducesResults() {
        let context = Context()
        defer { context.tearDown() }

        context.searchService.stubbedResults = [context.appResult()]
        context.viewModel.query = "weather"

        #expect(context.viewModel.hasQuery)
        #expect(context.viewModel.results.map(\.title) == ["Weather Station"])

        context.viewModel.clear()

        #expect(!context.viewModel.hasQuery)
        #expect(context.viewModel.results.isEmpty)
    }

    @Test("Setting the same query again does not re-run the search")
    func repeatedQueryDoesNotResearch() {
        let context = Context()
        defer { context.tearDown() }

        context.viewModel.query = "weather"
        let queryCount = context.searchService.queries.count

        context.viewModel.query = "weather"

        #expect(context.searchService.queries.count == queryCount)
    }

    @Test("The index follows the device manager and the platform preferences")
    func indexFollowsThePublishers() async {
        let context = Context()
        defer { context.tearDown() }

        let device = TestDataHelpers.createMockDevice(udid: "device-1", name: "iPhone 16")
        let recentApp = TestDataHelpers.createMockAppChange(device: device)

        context.deviceManager.setMockDevices([device])
        context.deviceManager.setMockRecentInstalledApps([recentApp])
        await context.settle()

        #expect(context.searchService.lastDevices.map(\.udid) == ["device-1"])
        #expect(context.searchService.lastRecentApps.count == 1)
        #expect(context.searchService.lastVisiblePlatforms.contains(.iPhone))

        context.settings.showIOS = false
        await context.settle()

        #expect(!context.searchService.lastVisiblePlatforms.contains(.iPhone))
    }

    @Test("A device change while a query is live refreshes the results")
    func deviceChangesRefreshLiveResults() async {
        let context = Context()
        defer { context.tearDown() }

        context.viewModel.query = "weather"
        #expect(context.viewModel.results.isEmpty)

        // Stands in for an app being installed in a running simulator while the panel is open.
        context.searchService.stubbedResults = [context.appResult()]
        context.deviceManager.setMockDevices([TestDataHelpers.createMockDevice()])
        await context.settle()

        #expect(context.viewModel.results.map(\.title) == ["Weather Station"])
    }

    @Test("Escape clears a query first, and asks to dismiss only once there is nothing left")
    func escapeClearsBeforeDismissing() {
        let context = Context()
        defer { context.tearDown() }

        context.viewModel.query = "weather"

        #expect(context.viewModel.cancel() == .clearedQuery)
        #expect(context.viewModel.query.isEmpty)

        #expect(context.viewModel.cancel() == .shouldDismiss)
    }
}

// MARK: - Helpers

@MainActor
private final class Context {
    let deviceManager: MockDeviceManager
    let searchService: MockMenuSearchService
    let settings: Settings
    let viewModel: MenuSearchViewModel

    private let suiteName: String

    init() {
        let suiteName = "MenuSearchViewModelTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults?.removePersistentDomain(forName: suiteName)

        let settings = Settings(userDefaults: userDefaults)
        let deviceManager = MockDeviceManager()
        let searchService = MockMenuSearchService()

        self.suiteName = suiteName
        self.settings = settings
        self.deviceManager = deviceManager
        self.searchService = searchService
        viewModel = MenuSearchViewModel(deviceManager: deviceManager,
                                        settings: settings,
                                        searchService: searchService)
    }

    func appResult() -> MenuSearchResult {
        let device = TestDataHelpers.createMockDevice(udid: "device-1", name: "iPhone 16", osVersion: "18.2")
        let app = TestDataHelpers.createMockApp(bundleIdentifier: "com.test.weather", displayName: "Weather Station")

        return MenuSearchResult(id: "app-com.test.weather-device-1",
                                kind: .app(app: app, device: device),
                                title: app.displayName,
                                subtitle: "iPhone 16 18.2",
                                iconName: app.iconName)
    }

    func settle(turns: Int = 3) async {
        await drainMainQueue(turns: turns)
    }

    func tearDown() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }
}
