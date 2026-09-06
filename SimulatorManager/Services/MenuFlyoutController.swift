//
//  MenuFlyoutController.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 06.09.26.
//

import AppKit
import SwiftUI

/// Decides *when* the flyout chain opens and closes, and keeps the windows in step with it.
///
/// The chain itself is not stored here. It is ``MenuPanelViewModel/pathIdentifiers`` — the same open
/// path the drill-down used — so a flyout is only a different way of drawing a level the navigation
/// model already knew about, and the keyboard needs no separate notion of where it is.
///
/// What this adds is the timing a real menu has and a hover has not: submenus open after a pause
/// rather than on the way past, and a pointer travelling diagonally into an open flyout is not
/// allowed to be intercepted by the rows it crosses.
@MainActor
final class MenuFlyoutController {
    struct Timing {
        /// Long enough that dragging the pointer down a list does not open every submenu it passes,
        /// short enough not to feel like waiting.
        var open: Duration = .milliseconds(180)
        /// Applied when the pointer lands on a row that has no submenu, so a flyout does not vanish
        /// the instant the pointer clips a neighbour on its way somewhere else.
        var close: Duration = .milliseconds(250)
        /// How long a flyout stays protected from the rows between it and the pointer.
        var safeTriangleGrace: Duration = .milliseconds(500)
    }

    var timing = Timing()
    /// Where the pointer is, in screen coordinates. Injected so the safe triangle can be tested
    /// without a mouse.
    var pointerLocation: () -> CGPoint = { NSEvent.mouseLocation }

    /// Opens `node`'s children as the flyout below the row at that depth.
    var openFlyout: ((MenuNode, Int) -> Void)?
    /// Closes every flyout deeper than that depth.
    var closeFlyouts: ((Int) -> Void)?

    private let presenter: any MenuFlyoutPresenting
    private var rowFrames: [String: CGRect] = [:]
    private var pendingTask: Task<Void, Never>?
    private var safeTriangle: MenuFlyoutSafeTriangle?
    private var safeTriangleDepth = 0
    private var safeTriangleDeadline: ContinuousClock.Instant?
    private var suppressedHover: (node: MenuNode, depth: Int)?

    init(presenter: any MenuFlyoutPresenting = MenuFlyoutPresenter()) {
        self.presenter = presenter
    }
}

// MARK: - Row geometry

extension MenuFlyoutController {
    /// Records where a row is, so a flyout can be hung off it.
    ///
    /// Only submenu rows are kept: nothing else can anchor a flyout, and the panel reports every row
    /// it lays out.
    func rowFrameChanged(_ frame: CGRect, for node: MenuNode) {
        guard node.isSubmenu else {
            return
        }

        rowFrames[node.id] = frame
    }
}

// MARK: - Hover

extension MenuFlyoutController {
    func hoverBegan(on node: MenuNode, depth: Int) {
        // The pointer is crossing this row on its way into a flyout that is already open. Ignoring
        // the hover is what makes a diagonal move work; re-applying it when the protection expires
        // is what stops the pointer from resting here and never being noticed.
        if isProtectingFlyout(against: depth) {
            suppressedHover = (node, depth)
            scheduleSafeTriangleExpiry()

            return
        }

        disarmSafeTriangle()
        pendingTask?.cancel()

        guard node.isSubmenu, node.isEnabled else {
            // Landing on an ordinary row means the user has moved on from whatever was open beside
            // this level.
            pendingTask = schedule(after: timing.close) { [weak self] in
                self?.closeFlyouts?(depth)
            }

            return
        }

        // The first submenu waits, so dragging the pointer down a list does not open every one it
        // passes. Once a flyout is up the user is already browsing submenus, and a menu swapped
        // those as fast as the pointer moved — waiting here leaves the old flyout standing under a
        // row the pointer has already left.
        guard !isFlyoutOpen(atDepth: depth) else {
            openFlyout?(node, depth)

            return
        }

        pendingTask = schedule(after: timing.open) { [weak self] in
            self?.openFlyout?(node, depth)
        }
    }

    /// Leaving a row does not close anything on its own — a menu you move away from stays open, and
    /// only landing somewhere else changes it. What it does do is protect the flyout this row is
    /// sitting beside, for as long as the pointer is plausibly heading into it.
    func hoverEnded(on node: MenuNode, depth: Int) {
        pendingTask?.cancel()
        pendingTask = nil

        if suppressedHover?.node.id == node.id {
            suppressedHover = nil
        }

        let frames = presenter.flyoutFrames

        guard frames.indices.contains(depth),
              let triangle = MenuFlyoutSafeTriangle(apex: pointerLocation(), flyoutFrame: frames[depth]) else {
            return
        }

        safeTriangle = triangle
        safeTriangleDepth = depth
        safeTriangleDeadline = ContinuousClock.now + timing.safeTriangleGrace
    }

    /// A click, or <kbd>→</kbd>: no waiting, and no triangle left standing in the way.
    func openImmediately(_ node: MenuNode, depth: Int) {
        pendingTask?.cancel()
        pendingTask = nil
        disarmSafeTriangle()
        openFlyout?(node, depth)
    }

    /// Drops whatever the pointer was about to do. Used when the keyboard takes over, where a
    /// submenu the pointer was drifting towards is no longer what the user is asking for.
    func cancelPending() {
        pendingTask?.cancel()
        pendingTask = nil
        suppressedHover = nil
        disarmSafeTriangle()
    }

    /// Closing the panel takes the whole chain with it, and leaves nothing behind to be positioned
    /// against windows that no longer exist.
    func reset() {
        cancelPending()
        rowFrames.removeAll()
        presenter.hideAll()
    }
}

// MARK: - Windows

extension MenuFlyoutController {
    /// Brings the windows in line with the open path.
    ///
    /// Called on every render rather than only when the path changes, so a level that gains or loses
    /// rows while it is open — an app installed in a running simulator, a finished cleanup — changes
    /// in the flyout too instead of being frozen at whatever it held when it opened.
    ///
    /// - Parameters:
    ///   - levels: The open levels, root first. `levels[index + 1]` is what flyout `index` shows.
    ///   - path: The identifiers of the rows that opened them.
    func synchronize(
        levels: [MenuPanelLevel],
        path: [String],
        rootWindow: NSWindow?,
        content: (Int, MenuPanelLevel, @escaping (CGSize) -> Void) -> AnyView
    ) {
        guard let rootWindow else {
            presenter.hideAll()

            return
        }

        for (index, identifier) in path.enumerated() {
            // A level whose anchor has not been laid out yet, or that resolved away because its
            // simulator was erased, ends the chain rather than being drawn against nothing.
            guard levels.indices.contains(index + 1), let anchorRowFrame = rowFrames[identifier] else {
                presenter.hideFlyouts(fromIndex: index)

                return
            }

            let level = levels[index + 1]

            presenter.show(atIndex: index, anchorRowFrame: anchorRowFrame, rootWindow: rootWindow) { report in
                content(index + 1, level, report)
            }
        }

        presenter.hideFlyouts(fromIndex: path.count)
    }
}

// MARK: - Safe triangle

private extension MenuFlyoutController {
    /// Whether the row at this depth already has a flyout beside it.
    func isFlyoutOpen(atDepth depth: Int) -> Bool {
        presenter.flyoutFrames.count > depth
    }

    /// Whether a hover at `depth` is the pointer passing through on its way into an open flyout.
    ///
    /// Only rows at or above the protected level are held off. A row inside the flyout itself is the
    /// destination, so reaching it disarms the protection rather than being blocked by it.
    func isProtectingFlyout(against depth: Int) -> Bool {
        guard let safeTriangle, let safeTriangleDeadline, depth <= safeTriangleDepth else {
            return false
        }
        guard ContinuousClock.now < safeTriangleDeadline else {
            disarmSafeTriangle()

            return false
        }

        return safeTriangle.contains(pointerLocation())
    }

    /// Re-applies a hover that the triangle swallowed, once the protection runs out.
    ///
    /// Without this, a pointer that stops inside the triangle would leave the wrong flyout open with
    /// no further hover events to correct it.
    func scheduleSafeTriangleExpiry() {
        guard let safeTriangleDeadline else {
            return
        }

        pendingTask?.cancel()
        pendingTask = schedule(after: max(.zero, ContinuousClock.now.duration(to: safeTriangleDeadline))) { [weak self] in
            guard let self, let hover = suppressedHover else {
                return
            }

            disarmSafeTriangle()
            suppressedHover = nil
            hoverBegan(on: hover.node, depth: hover.depth)
        }
    }

    func disarmSafeTriangle() {
        safeTriangle = nil
        safeTriangleDeadline = nil
        safeTriangleDepth = 0
    }

    func schedule(after duration: Duration, _ work: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        Task { @MainActor in
            try? await Task.sleep(for: duration)

            guard !Task.isCancelled else {
                return
            }

            work()
        }
    }
}
