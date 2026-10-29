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

    /// The window the panel is showing in, or `nil` when it is not showing. The flyouts are
    /// positioned against it, so the one place that knows how to find it hands it over rather than
    /// being reimplemented in a view.
    func panelWindow() -> NSWindow?
}

/// Opens and closes the `MenuBarExtra` panel programmatically.
///
/// SwiftUI does not expose an API for either, so the status item's button is located in the
/// application's window list by class name. Up to macOS 26 the button is then clicked, which is
/// public API.
///
/// From macOS 27 `MenuBarExtra` no longer opens its panel from the button's action. It is the status
/// item's `expandedInterfaceDelegate`, and the panel opens when the menu bar system begins an
/// expanded interface session. A click on the button only toggles its state. AppKit offers no public
/// way to begin a session, so the presenter reaches the status item and requests one through two
/// private selectors, each checked with `responds(to:)` first. Ending the session uses the public
/// `cancel()`.
///
/// All of this depends on implementation details of `MenuBarExtra` and AppKit, so it is isolated
/// behind ``MenuBarMenuPresenting``. If a future macOS release breaks it, `openMenu()` returns
/// `false` and the integration tests fail. The fallback is to manage the `NSStatusItem` directly
/// instead of swapping out the call sites.
@MainActor
final class MenuBarMenuPresenter: MenuBarMenuPresenting {
    /// How long ``openMenu()`` waits for the panel to appear before it stops trying to focus it.
    /// The menu bar system shows it within a few frames, so this only bounds a session that never
    /// begins.
    static let panelAppearanceTimeout: Duration = .seconds(1)

    private var focusTask: Task<Void, Never>?

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

        // Opening toggles the panel, which also gives the user a way to dismiss it again with the
        // same shortcut.
        if #available(macOS 27, *), let statusItem = Self.expandedInterfaceStatusItem(of: button) {
            if let session = statusItem.expandedInterfaceSession {
                session.cancel()
            } else if Self.requestExpandedInterfaceSession(for: statusItem) {
                // The menu bar system begins the session asynchronously, so the panel is not on
                // screen yet and there is nothing to focus.
                focusPanelOnceShown()
            } else {
                os_log("The status item cannot begin an expanded interface session, the menu cannot be opened programmatically")

                return false
            }
        } else {
            button.performClick(nil)
            focusPanel()
        }

        return true
    }

    /// Focuses the panel as soon as it appears, giving up after ``panelAppearanceTimeout``.
    ///
    /// SwiftUI reports nothing when it shows the panel, so the window list is checked on every
    /// frame until it does.
    private func focusPanelOnceShown() {
        let deadline = ContinuousClock.now + Self.panelAppearanceTimeout

        focusTask?.cancel()
        focusTask = Task { [weak self] in
            while ContinuousClock.now < deadline, !Task.isCancelled {
                if self?.focusPanel() ?? true {
                    return
                }

                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    /// Claims keyboard focus for the panel.
    ///
    /// Clicking the status item puts the panel on screen but does not make it the key window when
    /// the app was not already frontmost — which, for an agent app opened by a global shortcut, is
    /// the normal case. The panel would then be visible but deaf to the keyboard, and typing into
    /// it is the entire point of the shortcut.
    ///
    /// - Returns: `true` when the panel was showing and could be focused.
    @discardableResult
    func focusPanel() -> Bool {
        guard let window = panelWindow(), window.canBecomeKey else {
            return false
        }

        window.makeKeyAndOrderFront(nil)

        return true
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

        if #available(macOS 27, *), let statusItem = Self.expandedInterfaceStatusItem(of: button) {
            statusItem.expandedInterfaceSession?.cancel()

            return true
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
    /// Up to macOS 26, `MenuBarExtra` marks its status item button `on` for as long as its panel is
    /// up, the same way AppKit highlights a status item whose menu is open. From macOS 27 the button
    /// state no longer follows the panel, and the panel is showing exactly while the status item has
    /// an expanded interface session. Not private so the assumption is covered by an integration
    /// test rather than trusted.
    static func isShowingPanel(_ button: NSStatusBarButton) -> Bool {
        if #available(macOS 27, *), let statusItem = expandedInterfaceStatusItem(of: button) {
            return statusItem.expandedInterfaceSession != nil
        }

        return button.state == .on
    }

    /// The status item behind `button`, if its window is shown through an expanded interface session.
    ///
    /// `nil` when the item is not driven that way, as with the `NSMenu` style of `MenuBarExtra`, and
    /// when AppKit no longer exposes the item. Callers then fall back to clicking the button. Not
    /// private so an integration test can assert that the macOS 27 path is still reachable.
    @available(macOS 27, *)
    static func expandedInterfaceStatusItem(of button: NSStatusBarButton) -> NSStatusItem? {
        // Private: `NSStatusBarButton` has no public way back to its item.
        let selector = NSSelectorFromString("_statusItem")

        guard button.responds(to: selector),
              let statusItem = button.perform(selector)?.takeUnretainedValue() as? NSStatusItem,
              statusItem.expandedInterfaceDelegate != nil else {
            return nil
        }

        return statusItem
    }

    /// Whether the status item can be asked to begin an expanded interface session.
    @available(macOS 27, *)
    static func canRequestExpandedInterfaceSession(for statusItem: NSStatusItem) -> Bool {
        statusItem.responds(to: requestExpandedInterfaceSessionSelector)
    }
}

private extension MenuBarMenuPresenter {
    /// Private, and the only in-process way found to begin a session: clicking the button, a
    /// synthesized mouse event and the accessibility press all leave the session unbegun. The SDK
    /// has no public equivalent.
    static let requestExpandedInterfaceSessionSelector = NSSelectorFromString("_requestExpandedInterfaceSession")

    /// Asks the menu bar system to begin a session, which makes `MenuBarExtra` show its panel.
    /// - Returns: `false` when the status item no longer responds to the request.
    @available(macOS 27, *)
    static func requestExpandedInterfaceSession(for statusItem: NSStatusItem) -> Bool {
        guard canRequestExpandedInterfaceSession(for: statusItem) else {
            return false
        }

        statusItem.perform(requestExpandedInterfaceSessionSelector)

        return true
    }

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
