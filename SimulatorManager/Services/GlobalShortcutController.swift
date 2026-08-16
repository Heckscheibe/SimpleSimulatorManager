//
//  GlobalShortcutController.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 11.08.26.
//

import Combine
import Foundation
import os

/// Keeps the registered system wide hotkey in sync with the user's preference and opens the menu
/// bar menu when it fires.
@MainActor
class GlobalShortcutController: ObservableObject {
    /// Set when the current shortcut could not be claimed, so the settings window can explain why
    /// nothing happens when the user presses it.
    @Published private(set) var registrationErrorMessage: String?

    private let settings: Settings
    private let hotkeyService: GlobalHotkeyServing
    private let menuPresenter: MenuBarMenuPresenting
    private var cancellables = Set<AnyCancellable>()

    init(
        settings: Settings,
        hotkeyService: GlobalHotkeyServing,
        menuPresenter: MenuBarMenuPresenting
    ) {
        self.settings = settings
        self.hotkeyService = hotkeyService
        self.menuPresenter = menuPresenter

        observeShortcutChanges()
    }
}

private extension GlobalShortcutController {
    func observeShortcutChanges() {
        settings.$globalShortcut
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shortcut in
                self?.apply(shortcut)
            }
            .store(in: &cancellables)
    }

    func apply(_ shortcut: GlobalShortcut?) {
        guard let shortcut else {
            hotkeyService.unregister()
            registrationErrorMessage = nil

            return
        }

        do {
            try hotkeyService.register(shortcut) { [weak self] in
                self?.handleShortcutTriggered()
            }
            registrationErrorMessage = nil
        } catch {
            registrationErrorMessage = error.localizedDescription

            os_log("Global shortcut %{public}@ could not be registered: %{public}@",
                   shortcut.displayString,
                   error.localizedDescription)
        }
    }

    func handleShortcutTriggered() {
        guard !menuPresenter.openMenu() else {
            return
        }

        registrationErrorMessage = "The menu could not be opened. Please report this as a bug."
    }
}
