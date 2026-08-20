//
//  MenuBarMenuPresenterTests.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 11.08.26.
//

import AppKit
import Testing
@testable import SimulatorManager

/// Integration coverage for the one part of the global shortcut feature that relies on SwiftUI
/// internals rather than public API.
///
/// These tests run inside the host application, so the real `MenuBarExtra` status item exists.
/// If a future macOS or SwiftUI release changes how the status item is created, this suite fails
/// instead of the shortcut quietly doing nothing.
@Suite("MenuBarMenuPresenter Tests")
@MainActor
struct MenuBarMenuPresenterTests {
    @Test("The MenuBarExtra status item button can be located")
    func statusItemButtonIsReachable() {
        let presenter = MenuBarMenuPresenter()

        #expect(presenter.statusItemButton() != nil,
                "The status item could not be found, so the global shortcut would not be able to open the menu")
    }

    @Test("The located button belongs to a status bar window")
    func locatedButtonIsInStatusBar() throws {
        let presenter = MenuBarMenuPresenter()
        let button = try #require(presenter.statusItemButton())

        #expect(button.window != nil)
    }
}
