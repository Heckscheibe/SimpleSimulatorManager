//
//  MenuBarPanelTestSupport.swift
//  SimulatorManagerTests
//

import AppKit
@testable import SimulatorManager

/// How the integration tests in ``MenuBarPanelIntegrationTests`` open the real menu bar panel.
@MainActor
enum MenuBarPanelTestSupport {
    /// How long the panel's frame has to stay put before it counts as settled. Long enough to span
    /// a few frames, which is how long the panel takes to correct a size it was shown at.
    static let settleDuration: Duration = .milliseconds(100)

    /// Opens the panel and returns once it has settled: the status item reports a session, the
    /// window is visible, its rows have been measured, and its frame has stopped changing.
    ///
    /// The panel must never be closed in the same main-queue turn it first became visible. From
    /// macOS 27 doing so makes the menu bar system drop the *next* request for an expanded interface
    /// session about one time in three. No panel comes up, and the test after the one that closed
    /// too early times out waiting for it. The app cannot do that, since only a click or a second
    /// key press closes the panel. A test that returns on the first poll that sees the window can.
    ///
    /// Waiting for the size as well matters for the same reason: the panel comes up before its rows
    /// are measured, the first time at zero size, so anything placed against its frame while it
    /// grows ends up against a frame that no longer exists.
    ///
    /// - Returns: The panel's window, or `nil` when it never settled. The caller's `#require`
    ///   reports that with its own source location.
    static func openSettledPanel(with presenter: MenuBarMenuPresenter) async -> NSWindow? {
        presenter.openMenu()

        var lastFrame: CGRect?
        var stableSince = ContinuousClock.now

        await waitUntil {
            guard let window = presenter.panelWindow(), isMeasured(window), isShowingPanel(presenter) else {
                lastFrame = nil

                return false
            }
            guard window.frame == lastFrame else {
                lastFrame = window.frame
                stableSince = .now

                return false
            }

            return ContinuousClock.now - stableSince >= settleDuration
        }

        return presenter.panelWindow()
    }

    /// The flyout windows on screen right now: the ones whose frames the presenter reports.
    ///
    /// Matched by frame rather than counted, because AppKit creates windows of its own while the
    /// panel is up (text input, for one) and a count cannot tell those from a leaked flyout.
    static func flyoutWindows(of presenter: MenuFlyoutPresenter, besides panel: NSWindow) -> [NSWindow] {
        let frames = presenter.flyoutFrames

        return NSApp.windows.filter { window in
            window !== panel && window.isVisible && frames.contains(window.frame)
        }
    }
}

/// A window the test watches without keeping it alive.
@MainActor
final class WeakWindow {
    weak var window: NSWindow?

    init(_ window: NSWindow) {
        self.window = window
    }

    /// Whether the application still holds the window. One that has been deallocated does not.
    var isInApplicationWindowList: Bool {
        guard let window else {
            return false
        }

        return NSApp.windows.contains { $0 === window }
    }
}

private extension MenuBarPanelTestSupport {
    /// A panel that has not measured its rows yet is only as tall as its padding.
    static func isMeasured(_ window: NSWindow) -> Bool {
        (window.contentView?.bounds.height ?? 0) > MenuPanelStyle.rowMinimumHeight * 4
    }

    static func isShowingPanel(_ presenter: MenuBarMenuPresenter) -> Bool {
        guard let button = presenter.statusItemButton() else {
            return false
        }

        return MenuBarMenuPresenter.isShowingPanel(button)
    }
}
