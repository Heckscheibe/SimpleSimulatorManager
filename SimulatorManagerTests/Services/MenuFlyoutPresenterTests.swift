//
//  MenuFlyoutPresenterTests.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 06.09.26.
//

import AppKit
import SwiftUI
import Testing
@testable import SimulatorManager

/// Integration coverage for the one thing about flyouts that could not be settled on paper: whether
/// a window of ours can live beside the `MenuBarExtra` panel at all.
///
/// The panel dismisses itself when it stops being the key window, and a flyout is a window shown on
/// top of it. If that counts as the panel losing focus, the menu closes the instant a submenu opens
/// and the whole feature is dead. These tests run inside the host application against the real
/// panel, so a future macOS release that changes the answer fails here.
///
/// Nested inside ``MenuBarPanelIntegrationTests`` because that is what serializes it against the
/// other suite driving the same panel.
extension MenuBarPanelIntegrationTests {
    @Suite("MenuFlyoutPresenter Tests")
    @MainActor
    struct MenuFlyoutPresenterTests {
        @Test("Opening a flyout leaves the panel on screen")
        func flyoutDoesNotDismissThePanel() async throws {
            let menuPresenter = MenuBarMenuPresenter()
            let button = try #require(menuPresenter.statusItemButton())
            let flyouts = MenuFlyoutPresenter()
            defer {
                flyouts.hideAll()
                menuPresenter.closeMenu()
            }

            let panel = try await Self.openPanel(with: menuPresenter)

            Self.show(flyouts, atIndex: 0, rootWindow: panel)
            await waitUntil { flyouts.flyoutFrames.first != .zero }

            #expect(panel.isVisible, "The panel closed when a flyout opened, so submenus cannot be windows")
            #expect(MenuBarMenuPresenter.isShowingPanel(button),
                    "The status item stopped reporting the panel as open, so the next shortcut would reopen it")
        }

        @Test("A flyout is placed beside the panel, level with the row that opened it")
        func flyoutIsPlacedAgainstItsRow() async throws {
            let menuPresenter = MenuBarMenuPresenter()
            let flyouts = MenuFlyoutPresenter()
            defer {
                flyouts.hideAll()
                menuPresenter.closeMenu()
            }

            let panel = try await Self.openPanel(with: menuPresenter)

            Self.show(flyouts, atIndex: 0, rootWindow: panel)
            await waitUntil { flyouts.flyoutFrames.first != .zero }

            let frame = try #require(flyouts.flyoutFrames.first)
            let visibleFrame = try #require(panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame)
            let rowTop = panel.frame.maxY - Self.anchorRowFrame.minY

            #expect(frame.width == MenuPanelStyle.width)
            #expect(frame.height > MenuPanelStyle.rowMinimumHeight,
                    "The flyout collapsed to \(frame.height) points, so its rows are not being measured")
            #expect(frame.maxY == rowTop + MenuPanelStyle.listVerticalPadding)
            #expect(visibleFrame.contains(frame), "The flyout was placed off the screen at \(frame)")
        }

        @Test("A flyout is on screen by the time the hover that opened it returns")
        func flyoutIsShownWithoutALayoutRoundTrip() async throws {
            let menuPresenter = MenuBarMenuPresenter()
            let flyouts = MenuFlyoutPresenter()
            defer {
                flyouts.hideAll()
                menuPresenter.closeMenu()
            }

            let panel = try await Self.openPanel(with: menuPresenter)

            Self.show(flyouts, atIndex: 0, rootWindow: panel)

            // Deliberately nothing awaited between those two lines. Letting the contents report their
            // own size costs a layout pass, and another to act on it, which is the lag between the
            // pointer landing on a row and its submenu appearing — the reason there is no hover delay
            // either. A flyout that only measures itself later fails here.
            let frame = try #require(flyouts.flyoutFrames.first)

            #expect(frame != .zero, "The flyout was still invisible when the hover returned")
            #expect(frame.height > MenuPanelStyle.rowMinimumHeight,
                    "The flyout was shown at \(frame.height) points, so it was placed before its rows were measured")
        }

        @Test("A nested flyout hangs off the one above it, not off the panel")
        func nestedFlyoutHangsOffItsParent() async throws {
            let menuPresenter = MenuBarMenuPresenter()
            let flyouts = MenuFlyoutPresenter()
            defer {
                flyouts.hideAll()
                menuPresenter.closeMenu()
            }

            let panel = try await Self.openPanel(with: menuPresenter)

            Self.show(flyouts, atIndex: 0, rootWindow: panel)
            await waitUntil { flyouts.flyoutFrames.first != .zero }

            Self.show(flyouts, atIndex: 1, rootWindow: panel)
            await waitUntil { flyouts.flyoutFrames.count == 2 && flyouts.flyoutFrames[1] != .zero }

            let first = flyouts.flyoutFrames[0]
            let second = flyouts.flyoutFrames[1]

            // Beside its parent on one side or the other — which one depends on how much room is left,
            // and near the right of the menu bar there often is none.
            #expect(second.minX != first.minX, "The second flyout landed on top of the first")
            #expect(second.minX == first.maxX - MenuFlyoutGeometry.overlap
                || second.maxX == first.minX + MenuFlyoutGeometry.overlap)

            // And level with the row inside the first flyout that opened it. A flyout hung off a row
            // position measured before its own window had been sized landed most of a screen away.
            let rowTop = first.maxY - Self.anchorRowFrame.minY

            #expect(second.maxY == rowTop + MenuPanelStyle.listVerticalPadding,
                    "The nested flyout sits at \(second.maxY), nowhere near the row at \(rowTop)")
        }

        @Test("Closing the chain leaves no windows behind")
        func hidingLeavesNoWindowsBehind() async throws {
            let menuPresenter = MenuBarMenuPresenter()
            let flyouts = MenuFlyoutPresenter()
            defer { menuPresenter.closeMenu() }

            let panel = try await Self.openPanel(with: menuPresenter)
            // Windows closed by an earlier case in this suite can still be on their way out, so the
            // baseline is what the application settles at rather than what it holds this instant.
            await drainMainQueue(turns: 10)

            let windowCount = NSApp.windows.count

            Self.show(flyouts, atIndex: 0, rootWindow: panel)
            await waitUntil { flyouts.flyoutFrames.first != .zero }
            Self.show(flyouts, atIndex: 1, rootWindow: panel)
            await waitUntil { flyouts.flyoutFrames.count == 2 }

            flyouts.hideAll()
            await waitUntil { NSApp.windows.count <= windowCount }

            #expect(flyouts.flyoutFrames.isEmpty)
            // Not equality: a window from an earlier case draining in the meantime takes the count
            // *below* the baseline, which is not a failure. A leak is what takes it above — a panel
            // opened and dismissed all day would otherwise accumulate a window per submenu ever
            // hovered.
            #expect(NSApp.windows.count <= windowCount,
                    "\(NSApp.windows.count - windowCount) flyout windows outlived the chain")
        }
    }
}

private extension MenuBarPanelIntegrationTests.MenuFlyoutPresenterTests {
    /// A row partway down the panel, in the panel's own top-left-origin space.
    static let anchorRowFrame = CGRect(x: 0, y: 60, width: MenuPanelStyle.width, height: 22)

    static func openPanel(with presenter: MenuBarMenuPresenter) async throws -> NSWindow {
        presenter.openMenu()
        await waitUntil { presenter.panelWindow() != nil }

        return try #require(presenter.panelWindow(),
                            "The `.window`-style MenuBarExtra did not produce a panel window")
    }

    static func show(_ presenter: MenuFlyoutPresenter, atIndex index: Int, rootWindow: NSWindow) {
        presenter.show(atIndex: index, anchorRowFrame: anchorRowFrame, rootWindow: rootWindow) { reportSize in
            AnyView(MenuFlyoutContentView(nodes: nodes(), handlers: handlers(), sizeChanged: reportSize))
        }
    }

    static func nodes() -> [MenuNode] {
        (0 ..< 4).map { index in
            .action(id: "row-\(index)", title: "Row \(index)") {}
        }
    }

    static func handlers() -> MenuRowHandlers {
        MenuRowHandlers(depth: 1,
                        isHighlighted: { _, _ in false },
                        isAwaitingConfirmation: { _ in false },
                        hoverChanged: { _, _ in },
                        frameChanged: { _, _ in },
                        activate: { _ in })
    }
}
