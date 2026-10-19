//
//  MenuBarMenuPresenter.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 11.08.26.
//

import AppKit
import Foundation
import os

@MainActor
protocol MenuBarMenuPresenting: AnyObject {
    /// Opens the menu bar panel, or closes it again if it is already showing.
    /// - Returns: `true` when the status item could be reached, `false` otherwise.
    @discardableResult
    func openMenu() -> Bool

    /// Closes the panel if it is showing, and does nothing if it is not.
    /// - Returns: `true` when the status item could be reached, `false` otherwise.
    @discardableResult
    func closeMenu() -> Bool
}

/// Opens and closes the `MenuBarExtra` panel programmatically.
///
/// SwiftUI does not expose an API for either, so the status item's button is located in the
/// application's window list and clicked. `NSStatusBarButton` is public API and the status bar
/// window is found by class name only, so no private property access is involved — but this still
/// depends on an implementation detail of `MenuBarExtra` and is therefore isolated behind
/// ``MenuBarMenuPresenting``. If a future macOS release breaks it, the fallback is to manage the
/// `NSStatusItem` directly instead of swapping out the call sites.
@MainActor
final class MenuBarMenuPresenter: MenuBarMenuPresenting {
    @discardableResult
    func openMenu() -> Bool {
        guard let button = statusItemButton() else {
            os_log("Could not locate the status item button, the menu cannot be opened programmatically")

            return false
        }

        // The panel is a real window and this app is an agent (LSUIElement), so it is never brought
        // forward on its own. Without activating, the panel opens without keyboard focus and
        // anything the user types goes to the app they were in.
        NSApp.activate()

        // Clicking the status item toggles the panel, which also gives the user a way to dismiss it
        // again with the same shortcut.
        button.performClick(nil)
        focusPanel()

        return true
    }

    /// Claims keyboard focus for the panel.
    ///
    /// Clicking the status item puts the panel on screen but does not make it the key window when
    /// the app was not already frontmost — which, for an agent app opened by a global shortcut, is
    /// the normal case. The panel would then be visible but deaf to the keyboard, and typing into
    /// it is the entire point of the shortcut.
    func focusPanel() {
        guard let window = panelWindow(), window.canBecomeKey else {
            return
        }

        window.makeKeyAndOrderFront(nil)
    }

    /// The window `MenuBarExtra` shows in `.window` style.
    ///
    /// Found by class name, like the status bar window above, and for the same reason: SwiftUI
    /// exposes no handle on it. Not private so an integration test can assert it exists rather than
    /// leaving a silent failure here to surface as a panel that ignores the keyboard.
    func panelWindow() -> NSWindow? {
        NSApp.windows.first { window in
            NSStringFromClass(type(of: window)).contains("MenuBarExtraWindow") && window.isVisible
        }
    }

    @discardableResult
    func closeMenu() -> Bool {
        guard let button = statusItemButton() else {
            os_log("Could not locate the status item button, the menu cannot be closed programmatically")

            return false
        }

        // Clicking toggles, so the state has to be checked first or closing a panel that is already
        // closed would open it.
        guard Self.isShowingPanel(button) else {
            return true
        }

        button.performClick(nil)

        return true
    }

    /// Locates the button of the `MenuBarExtra` status item.
    ///
    /// Not private so that it can be covered by an integration test: this lookup is the one part
    /// of the feature that depends on SwiftUI internals, and a silent failure here would leave the
    /// shortcut doing nothing at all.
    func statusItemButton() -> NSStatusBarButton? {
        for window in NSApp.windows where Self.isStatusBarWindow(window) {
            if let button = Self.firstStatusBarButton(in: window.contentView) {
                return button
            }
        }

        return nil
    }

    /// Whether the panel is currently showing.
    ///
    /// `MenuBarExtra` marks its status item button `on` for as long as its panel is up, the same
    /// way AppKit highlights a status item whose menu is open. Not private so the assumption is
    /// covered by an integration test rather than trusted.
    static func isShowingPanel(_ button: NSStatusBarButton) -> Bool {
        button.state == .on
    }
}

private extension MenuBarMenuPresenter {
    static func isStatusBarWindow(_ window: NSWindow) -> Bool {
        NSStringFromClass(type(of: window)).contains("NSStatusBarWindow")
    }

    static func firstStatusBarButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else {
            return nil
        }

        if let button = view as? NSStatusBarButton {
            return button
        }

        for subview in view.subviews {
            if let button = firstStatusBarButton(in: subview) {
                return button
            }
        }

        return nil
    }
}
