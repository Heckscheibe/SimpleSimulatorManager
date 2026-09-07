//
//  MenuFlyoutPresenter.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 06.09.26.
//

import AppKit
import SwiftUI

/// Shows the open submenus of the menu bar panel as windows beside it.
@MainActor
protocol MenuFlyoutPresenting: AnyObject {
    /// The open flyouts in screen coordinates, shallowest first. The safe triangle has to know where
    /// the flyout the pointer is heading for actually is.
    var flyoutFrames: [CGRect] { get }

    /// Shows the flyout opened by a row at `index`, creating it if it is not already up.
    ///
    /// - Parameters:
    ///   - anchorRowFrame: The opening row's frame in its own window's SwiftUI space.
    ///   - rootWindow: The panel. Flyouts deeper than the first hang off the flyout above them.
    ///   - content: Builds the flyout's contents. It is handed a callback to report the size it
    ///     wants, because a `ScrollView` has no intrinsic height and nothing else can measure it.
    func show(
        atIndex index: Int,
        anchorRowFrame: CGRect,
        rootWindow: NSWindow,
        content: (@escaping (CGSize) -> Void) -> AnyView
    )

    /// Closes the flyout at `index` and everything deeper.
    func hideFlyouts(fromIndex index: Int)
}

extension MenuFlyoutPresenting {
    func hideAll() {
        hideFlyouts(fromIndex: 0)
    }
}

/// Puts each open submenu in its own borderless panel.
///
/// The panels are deliberately never made key. The menu bar panel dismisses itself when it stops
/// being the key window, so a flyout that took focus would close the menu it belongs to — and the
/// search field has to keep first responder anyway, or typing stops filtering. Ordering above the
/// parent by window number, without activating, is what makes both work at once.
@MainActor
final class MenuFlyoutPresenter: MenuFlyoutPresenting {
    /// One open flyout: its window, the row it hangs off, and whether its contents have reported a
    /// size yet.
    private final class Flyout {
        let panel: NSPanel
        var rowFrame: CGRect = .zero
        var parent: NSWindow
        /// A flyout is put on screen transparent and only faded in once it has been measured. SwiftUI
        /// does not lay out a view that was never added to a visible window, so it cannot be measured
        /// first and shown second — and showing it at a guessed size would snap to the real one in
        /// front of the user.
        var isSized = false

        init(panel: NSPanel, parent: NSWindow) {
            self.panel = panel
            self.parent = parent
        }
    }

    private var flyouts: [Flyout] = []

    var flyoutFrames: [CGRect] {
        // An unmeasured flyout is invisible, and the safe triangle must not aim the pointer at it.
        flyouts.map { $0.isSized ? $0.panel.frame : .zero }
    }

    func show(
        atIndex index: Int,
        anchorRowFrame: CGRect,
        rootWindow: NSWindow,
        content: (@escaping (CGSize) -> Void) -> AnyView
    ) {
        // A flyout can only hang off a window that is already up, so a gap in the chain — a level
        // whose anchor has not been laid out yet — closes everything from there down rather than
        // leaving an orphan on screen.
        guard let parent = parentWindow(forIndex: index, rootWindow: rootWindow) else {
            hideFlyouts(fromIndex: index)

            return
        }

        let flyout = flyout(atIndex: index, parent: parent, level: rootWindow.level)

        flyout.rowFrame = anchorRowFrame
        flyout.parent = parent
        // Replacing the root view rather than the whole hosting view, so SwiftUI diffs the rows
        // instead of rebuilding them: this runs on every render of the panel, which is what carries
        // a change that lands while a flyout is open — an app installed in a running simulator —
        // into the flyout as well.
        let hostingView = hostingView(of: flyout.panel)

        hostingView.rootView = content { [weak self] size in
            self?.place(index: index, size: size)
        }

        // Sized and shown in this same turn. Waiting for the contents to report their own size costs
        // a layout round trip, and that round trip is the lag between the pointer landing on a row
        // and its submenu appearing — the whole reason there is no hover delay either.
        hostingView.layoutSubtreeIfNeeded()
        place(index: index, size: hostingView.fittingSize)
    }

    func hideFlyouts(fromIndex index: Int) {
        guard flyouts.count > index else {
            return
        }

        for flyout in flyouts[index...] {
            // Closed rather than only ordered out, so a panel opened and dismissed a hundred times
            // does not leave a hundred windows behind it.
            flyout.panel.close()
        }

        flyouts.removeSubrange(index...)
    }
}

private extension MenuFlyoutPresenter {
    /// The first flyout hangs off the panel; every deeper one hangs off the flyout above it.
    func parentWindow(forIndex index: Int, rootWindow: NSWindow) -> NSWindow? {
        guard index > 0 else {
            return rootWindow
        }
        guard flyouts.indices.contains(index - 1) else {
            return nil
        }

        return flyouts[index - 1].panel
    }

    /// Flyouts are only ever appended one past the end: ``show(atIndex:anchorRowFrame:rootWindow:content:)``
    /// walks the chain in order, and a gap closes everything below it.
    private func flyout(atIndex index: Int, parent: NSWindow, level: NSWindow.Level) -> Flyout {
        if flyouts.indices.contains(index) {
            return flyouts[index]
        }

        let panel = Self.makePanel(level: level)
        let flyout = Flyout(panel: panel, parent: parent)

        // Ordered in transparent, and off the parent's own edge, so SwiftUI lays its contents out —
        // which is the only way to find out how big they are — without any of that being visible.
        panel.setContentSize(CGSize(width: MenuPanelStyle.width, height: MenuPanelStyle.maximumListHeight))
        panel.setFrameOrigin(CGPoint(x: parent.frame.maxX, y: parent.frame.minY))
        panel.order(.above, relativeTo: parent.windowNumber)
        flyouts.append(flyout)

        return flyout
    }

    func hostingView(of panel: NSPanel) -> NSHostingView<AnyView> {
        if let existing = panel.contentView as? NSHostingView<AnyView> {
            return existing
        }

        let hostingView = NSHostingView(rootView: AnyView(EmptyView()))

        panel.contentView = hostingView

        return hostingView
    }

    /// Sizes and places a flyout once its contents know how tall they are, and only then makes it
    /// visible.
    func place(index: Int, size: CGSize) {
        guard flyouts.indices.contains(index) else {
            return
        }

        let flyout = flyouts[index]
        // The floor keeps a level that has not been laid out yet off the screen rather than showing
        // it as a sliver; the cap is what makes a submenu with two dozen apps scroll.
        let height = min(max(size.height, MenuPanelStyle.rowMinimumHeight), MenuPanelStyle.maximumListHeight)
        let size = CGSize(width: MenuPanelStyle.width, height: height)
        let parentFrame = flyout.parent.frame
        let visibleFrame = flyout.parent.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? parentFrame
        let anchorFrame = MenuFlyoutGeometry.screenFrame(forRow: flyout.rowFrame, inWindow: parentFrame)
        let frame = MenuFlyoutGeometry.frame(ofSize: size,
                                             anchoredTo: anchorFrame,
                                             besideWindow: parentFrame,
                                             onScreen: visibleFrame,
                                             alignmentInset: MenuPanelStyle.listVerticalPadding)

        flyout.panel.setFrame(frame, display: true)
        flyout.panel.alphaValue = 1
        flyout.isSized = true
    }

    static func makePanel(level: NSWindow.Level) -> NSPanel {
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)

        panel.isFloatingPanel = true
        panel.level = level
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        // Invisible until its contents have been measured.
        panel.alphaValue = 0
        // The flyout follows the menu it belongs to rather than being hidden the moment something
        // else in the system takes over.
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isMovable = false
        // Closing is how a flyout goes away, and AppKit's own release-on-close predates ARC.
        panel.isReleasedWhenClosed = false
        // A click on a row must not pull focus out of the search field — and taking key would make
        // the menu bar panel dismiss itself.
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .none

        return panel
    }
}
