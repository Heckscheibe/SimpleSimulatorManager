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
/// A submenu opens the moment the pointer lands on it. What this adds is the two things a plain
/// hover still gets wrong: a flyout does not vanish the instant the pointer clips a neighbour on its
/// way elsewhere, and a pointer travelling diagonally into an open flyout is not intercepted by the
/// rows it crosses on the way.
@MainActor
final class MenuFlyoutController {
    struct Timing {
        /// Applied when the pointer lands on a row that has no submenu, so a flyout does not vanish
        /// the instant the pointer clips a neighbour on its way somewhere else. There is deliberately
        /// no counterpart for opening: a submenu the pointer is on is one the user is asking for, and
        /// any wait at all leaves the previous flyout standing under a row they have already left.
        var close: Duration = .milliseconds(250)
        /// The longest a flyout stays protected from the rows between it and the pointer, however
        /// steadily the pointer keeps closing in on it.
        var safeTriangleGrace: Duration = .milliseconds(500)
        /// How long the pointer may go without getting any closer to the protected flyout before the
        /// row it is on is taken up. A pointer heading into the flyout closes in on it every few
        /// milliseconds; one that has stopped, or is travelling along the panel instead, has picked
        /// the row it is on — and making it sit out the whole grace first is a submenu opening late.
        var safeTriangleStall: Duration = .milliseconds(60)
        /// How often the pointer is looked at while a hover is held off. Hover only reports crossing
        /// into a row, so without looking nothing would notice the pointer leaving the triangle or
        /// stopping inside it.
        var pointerSampling: Duration = .milliseconds(8)
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
    /// What each open flyout is currently showing, so an unchanged one is left alone.
    private var shownSignatures: [Int] = []

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
            watchSuppressedHover()

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

        // A submenu whose opening starts work (``MenuNode/onEnter``) opens just as promptly. That work
        // runs in the background and only once — the cleanup scan is skipped after it has loaded — so
        // the pointer crossing its row costs a scan at most once, where a wait cost every opening.
        //
        // Swapping the flyout at this depth reuses its window rather than tearing one down and
        // building another, so sweeping the pointer down a list of submenus costs a re-render each,
        // not a window each.
        openFlyout?(node, depth)
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

    /// Closing the panel takes the whole chain with it.
    ///
    /// The row frames deliberately survive. Closing the panel hides its window but does not tear
    /// down the view inside it, so on the next opening the rows are laid out at the positions they
    /// already had — and `onGeometryChange` reports a *change*, so it says nothing at all. Throwing
    /// the frames away here left the second opening with nowhere to hang a flyout.
    func reset() {
        cancelPending()
        close(fromIndex: 0)
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
        content: (String, Int, MenuPanelLevel, @escaping (CGSize) -> Void) -> AnyView
    ) {
        guard let rootWindow else {
            close(fromIndex: 0)

            return
        }

        var signatures: [Int] = []

        for (index, identifier) in path.enumerated() {
            // A level whose anchor has not been laid out yet, or that resolved away because its
            // simulator was erased, ends the chain rather than being drawn against nothing.
            guard levels.indices.contains(index + 1), let anchorRowFrame = rowFrames[identifier] else {
                close(fromIndex: index)

                return
            }

            let level = levels[index + 1]
            let signature = Self.signature(of: level,
                                           anchoredTo: anchorRowFrame,
                                           hangingOffFrame: parentFrame(forIndex: index, rootWindow: rootWindow))

            signatures.append(signature)

            // Pushing content a flyout is already showing is not free — it re-renders and re-lays
            // out that window. This runs on every render of the panel, which includes every hover,
            // so an unchanged level has to cost nothing.
            guard shownSignatures.indices.contains(index) == false || shownSignatures[index] != signature else {
                continue
            }

            presenter.show(atIndex: index, anchorRowFrame: anchorRowFrame, rootWindow: rootWindow) { report in
                content(identifier, index + 1, level, report)
            }
        }

        close(fromIndex: path.count)
        shownSignatures = signatures
    }
}

// MARK: - Safe triangle

private extension MenuFlyoutController {
    func close(fromIndex index: Int) {
        presenter.hideFlyouts(fromIndex: index)
        shownSignatures = Array(shownSignatures.prefix(index))
    }

    /// The window flyout `index` hangs off, on screen. A flyout is placed against it, so one that
    /// moved or resized takes the flyouts below it with it.
    func parentFrame(forIndex index: Int, rootWindow: NSWindow) -> CGRect {
        guard index > 0 else {
            return rootWindow.frame
        }

        let frames = presenter.flyoutFrames

        return frames.indices.contains(index - 1) ? frames[index - 1] : .zero
    }

    /// Everything about a level that changes what its window looks like or where it sits. The
    /// actions' closures are left out on purpose: they close over view models by reference, so a
    /// row keeps doing the right thing without the window being rebuilt to hear about it. Their
    /// titles are not, because a row gaining or losing an action is a change to the row.
    static func signature(of level: MenuPanelLevel, anchoredTo anchor: CGRect, hangingOffFrame parent: CGRect) -> Int {
        var hasher = Hasher()

        hasher.combine(anchor.minX)
        hasher.combine(anchor.minY)
        hasher.combine(parent.minX)
        hasher.combine(parent.minY)
        hasher.combine(parent.width)
        hasher.combine(parent.height)

        for node in level.nodes {
            hasher.combine(node.id)
            hasher.combine(node.title)
            hasher.combine(node.subtitle)
            hasher.combine(node.iconName)
            hasher.combine(node.isSubmenu)
            hasher.combine(node.isEnabled)
            hasher.combine(node.isDestructive)
            hasher.combine(node.actions.map(\.title))
        }

        return hasher.finalize()
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

    /// Re-applies a hover that the triangle swallowed as soon as the pointer is no longer heading into
    /// the flyout: it left the triangle, it stopped closing in on the flyout, or the protection ran
    /// out.
    ///
    /// Without this, a pointer that stops inside the triangle would leave the wrong flyout open with
    /// no further hover events to correct it. Waiting for the protection to run out instead made a
    /// row the pointer settled on beside an open flyout open its submenu up to half a second late.
    func watchSuppressedHover() {
        guard let safeTriangle, let safeTriangleDeadline else {
            return
        }

        pendingTask?.cancel()
        pendingTask = Task { @MainActor [weak self] in
            var approach = MenuFlyoutApproach(towardsEdgeAt: safeTriangle.baseTop.x)

            while !Task.isCancelled {
                guard let self else {
                    return
                }

                let now = ContinuousClock.now
                let pointer = pointerLocation()

                approach.record(pointer, at: now)

                if now >= safeTriangleDeadline
                    || !safeTriangle.contains(pointer)
                    || approach.hasStalled(at: now, after: timing.safeTriangleStall) {
                    applySuppressedHover()

                    return
                }

                try? await Task.sleep(for: timing.pointerSampling)
            }
        }
    }

    func applySuppressedHover() {
        guard let hover = suppressedHover else {
            return
        }

        disarmSafeTriangle()
        suppressedHover = nil
        hoverBegan(on: hover.node, depth: hover.depth)
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
