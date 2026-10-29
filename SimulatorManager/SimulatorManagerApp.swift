//
//  SimulatorManagerApp.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 11.10.23.
//

import SwiftUI
import os
import SimulatorCore

@main
struct SimulatorManagerApp: App {
    @StateObject private var deviceManager: DeviceManager
    @State private var viewModel: SimulatorManagerViewModel
    @State private var cleanupSimulatorsViewModel: CleanupSimulatorsViewModel
    @State private var cleanupRuntimesViewModel: CleanupRuntimesViewModel
    @State private var resetSimulatorsViewModel: ResetSimulatorsViewModel
    @State private var settingsViewModel: SettingsViewModel
    @State private var shortcutRecorderViewModel: ShortcutRecorderViewModel
    @State private var menuSearchViewModel: MenuSearchViewModel
    @State private var snapshotSaveViewModel: SnapshotSaveViewModel
    @State private var agentIntegrationViewModel = AgentIntegrationViewModel()
    @StateObject private var settings: Settings
    @StateObject private var shortcutController: GlobalShortcutController
    @StateObject private var githubService = GithubService()

    private let simulatorResetService: SimulatorResetServing
    private let simulatorCleanupService: SimulatorCleanupServing
    /// Shared between the global shortcut, which opens the panel, and the panel itself, which
    /// closes it after a row is picked.
    private let menuPresenter: MenuBarMenuPresenting

    init() {
        let deviceManager = DeviceManager()
        let simulatorResetService: SimulatorResetServing = SimulatorResetService()
        let simulatorCleanupService: SimulatorCleanupServing = SimulatorCleanupService()
        let viewModel = SimulatorManagerViewModel(deviceManager: deviceManager,
                                                  simulatorResetService: simulatorResetService)
        let cleanupSimulatorsViewModel = CleanupSimulatorsViewModel(cleanupService: simulatorCleanupService,
                                                                    deviceManager: deviceManager)
        let cleanupRuntimesViewModel = CleanupRuntimesViewModel(
            cleanupService: SimulatorRuntimeCleanupService(),
            deviceManager: deviceManager,
            // Removing a runtime leaves its simulators unavailable, which the simulator cleanup
            // list should pick up without waiting for a manual refresh.
            didDeleteRuntimes: { cleanupSimulatorsViewModel.refreshCleanupCandidates() }
        )
        let resetSimulatorsViewModel = ResetSimulatorsViewModel(deviceManager: deviceManager,
                                                                simulatorResetService: simulatorResetService)
        let settings = Settings()
        let menuPresenter = MenuBarMenuPresenter()

        let shortcutController = GlobalShortcutController(settings: settings,
                                                          hotkeyService: GlobalHotkeyService(),
                                                          menuPresenter: menuPresenter)

        self.simulatorResetService = simulatorResetService
        self.simulatorCleanupService = simulatorCleanupService
        self.menuPresenter = menuPresenter
        self._deviceManager = StateObject(wrappedValue: deviceManager)
        self._viewModel = State(initialValue: viewModel)
        self._cleanupSimulatorsViewModel = State(initialValue: cleanupSimulatorsViewModel)
        self._cleanupRuntimesViewModel = State(initialValue: cleanupRuntimesViewModel)
        self._resetSimulatorsViewModel = State(initialValue: resetSimulatorsViewModel)
        self._settingsViewModel = State(initialValue: SettingsViewModel(settings: settings,
                                                                        simulatorManagerViewModel: viewModel))
        self._shortcutRecorderViewModel = State(initialValue: ShortcutRecorderViewModel(settings: settings))
        self._menuSearchViewModel = State(initialValue: MenuSearchViewModel(deviceManager: deviceManager,
                                                                            settings: settings))
        self._snapshotSaveViewModel = State(initialValue: SnapshotSaveViewModel(settings: settings))
        self._settings = StateObject(wrappedValue: settings)
        self._shortcutController = StateObject(wrappedValue: shortcutController)
    }

    var body: some Scene {
        searchablePanelScene

        // A `Window` rather than a SwiftUI `Settings` scene: see `PreferencesWindow` for why the
        // latter cannot present in this app.
        Window("Settings", id: PreferencesWindow.identifier) {
            PreferencesView(settings: settings,
                            shortcutController: shortcutController,
                            recorderViewModel: shortcutRecorderViewModel,
                            agentIntegrationViewModel: agentIntegrationViewModel)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

// MARK: - Menu bar scenes

private extension SimulatorManagerApp {
    /// The searchable panel. `.window` rather than the default `.menu` style: a real `NSMenu`
    /// cannot filter its items as the user types, and no API makes it do so.
    var searchablePanelScene: some Scene {
        MenuBarExtra("SimulatorManager", systemImage: Self.menuBarSymbol) {
            MenuPanelView(simulatorManagerViewModel: viewModel,
                          settingsViewModel: settingsViewModel,
                          cleanupViewModel: cleanupSimulatorsViewModel,
                          cleanupRuntimesViewModel: cleanupRuntimesViewModel,
                          resetViewModel: resetSimulatorsViewModel,
                          snapshotSaveViewModel: snapshotSaveViewModel,
                          settings: settings,
                          githubService: githubService,
                          menuPresenter: menuPresenter,
                          searchViewModel: menuSearchViewModel)
        }
        .menuBarExtraStyle(.window)
    }

    static let menuBarSymbol = "iphone.gen3"
}
