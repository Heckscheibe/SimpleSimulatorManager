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
    /// Opens the menu bar menu.
    /// - Returns: `true` when the status item could be reached, `false` otherwise.
    @discardableResult
    func openMenu() -> Bool
}

/// Opens the `MenuBarExtra` menu programmatically.
///
/// SwiftUI does not expose an API to open a `MenuBarExtra`, so the status item's button is located
/// in the application's window list and clicked. `NSStatusBarButton` is public API and the status
/// bar window is found by class name only, so no private property access is involved — but this
/// still depends on an implementation detail of `MenuBarExtra` and is therefore isolated behind
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

        // Clicking the status item toggles the menu, which also gives the user a way to dismiss it
        // again with the same shortcut.
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
