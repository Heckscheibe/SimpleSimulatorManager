//
//  MenuBarMenuPresenterTests.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 11.08.26.
//

import AppKit
import Testing
@testable import SimulatorManager

/// Integration coverage for the parts of the menu bar panel that rely on SwiftUI internals rather
/// than public API.
///
/// These tests run inside the host application, so the real `MenuBarExtra` status item and its
/// panel exist. If a future macOS or SwiftUI release changes how either is created, this suite
/// fails instead of the shortcut quietly doing nothing.
///
/// Serialized because they open and close the one shared panel.
@Suite("MenuBarMenuPresenter Tests", .serialized)
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

    @Test("Opening puts the panel window on screen and marks the status item as showing it")
    func openingShowsThePanel() async throws {
        let presenter = MenuBarMenuPresenter()
        let button = try #require(presenter.statusItemButton())
        defer { presenter.closeMenu() }

        #expect(!MenuBarMenuPresenter.isShowingPanel(button))

        presenter.openMenu()
        await waitUntil { presenter.panelWindow() != nil }

        let window = try #require(presenter.panelWindow(),
                                  "The `.window`-style MenuBarExtra did not produce a panel window")

        #expect(window.isVisible)
        #expect(MenuBarMenuPresenter.isShowingPanel(button),
                "The status item is not marked as showing, so closeMenu would reopen the panel instead of closing it")
        // The panel is only usable from the keyboard if it is allowed to become key. Whether it
        // actually does depends on the app being active, which a test host never is.
        #expect(window.canBecomeKey)
    }

    @Test("The panel is sized to its contents rather than collapsing")
    func panelHasARealSize() async throws {
        let presenter = MenuBarMenuPresenter()
        defer { presenter.closeMenu() }

        presenter.openMenu()
        await waitUntil { presenter.panelWindow() != nil }

        let window = try #require(presenter.panelWindow())
        let contentView = try #require(window.contentView)

        #expect(contentView.bounds.width == MenuPanelStyle.width)
        // A `ScrollView` has no intrinsic height and the panel's window imposes none, so a panel
        // that does not measure its own rows collapses to the height of its padding alone.
        #expect(contentView.bounds.height > MenuPanelStyle.rowMinimumHeight * 4,
                "The panel collapsed to \(contentView.bounds.height) points, so its rows are not being measured")
        #expect(contentView.bounds.height <= MenuPanelStyle.maximumListHeight,
                "The panel grew past its cap, so a machine with many simulators would get a panel taller than the screen")
    }

    @Test("Closing hides the panel, and closing again does not reopen it")
    func closingHidesThePanel() async throws {
        let presenter = MenuBarMenuPresenter()
        let button = try #require(presenter.statusItemButton())
        defer { presenter.closeMenu() }

        presenter.openMenu()
        await waitUntil { presenter.panelWindow() != nil }

        let window = try #require(presenter.panelWindow())

        #expect(presenter.closeMenu())
        await waitUntil { !window.isVisible }

        #expect(!window.isVisible)
        #expect(!MenuBarMenuPresenter.isShowingPanel(button))

        // Clicking the status item toggles, so a close that did not check first would open the
        // panel back up.
        #expect(presenter.closeMenu())
        await drainMainQueue()

        #expect(!window.isVisible)
        #expect(!MenuBarMenuPresenter.isShowingPanel(button))
    }
}
