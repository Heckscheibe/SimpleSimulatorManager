//
//  MenuNodeRowsView.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 06.09.26.
//

import SwiftUI

/// What a row reports back to whoever is drawing it.
///
/// The panel and a flyout draw the same rows and have to treat them identically — one highlight, one
/// activation path, one place a hover is interpreted — but they are separate windows and cannot
/// share a view hierarchy. Passing the behaviour in keeps the two from drifting apart.
struct MenuRowHandlers {
    /// The depth of the level being drawn. `0` is the panel; every flyout is one deeper.
    let depth: Int
    /// Takes the whole level, because whether a row on the open path still counts as highlighted
    /// depends on whether the pointer has landed on one of its siblings.
    let isHighlighted: (MenuNode, [MenuNode]) -> Bool
    let isAwaitingConfirmation: (MenuNode) -> Bool
    let hoverChanged: (MenuNode, Bool) -> Void
    /// The row's frame in its own window, so a flyout can be hung off it.
    let frameChanged: (MenuNode, CGRect) -> Void
    let activate: (MenuNode) -> Void
}

extension MenuRowHandlers {
    /// A copy that says nothing about where its rows are.
    ///
    /// A flyout is ordered in at a placeholder size and only sized once its rows have been measured.
    /// Until that has happened the rows are laid out against a window that is the wrong height and
    /// sit wherever it centres them, so their positions are meaningless — and hanging a further
    /// flyout off one of those positions puts it somewhere else entirely on the screen.
    func withoutRowFrames() -> MenuRowHandlers {
        MenuRowHandlers(depth: depth,
                        isHighlighted: isHighlighted,
                        isAwaitingConfirmation: isAwaitingConfirmation,
                        hoverChanged: hoverChanged,
                        frameChanged: { _, _ in },
                        activate: activate)
    }
}

/// One level's rows, in the order the tree gave them.
struct MenuNodeRowsView: View {
    let nodes: [MenuNode]
    let handlers: MenuRowHandlers

    var body: some View {
        // A plain stack rather than a lazy one: a single menu level is small, and rendering it
        // eagerly keeps scroll-into-view working, which a `LazyVStack` breaks by not materialising
        // rows that are not on screen.
        VStack(alignment: .leading, spacing: 0) {
            ForEach(nodes) { node in
                MenuPanelRowView(node: node,
                                 isSelected: handlers.isHighlighted(node, nodes),
                                 isAwaitingConfirmation: handlers.isAwaitingConfirmation(node),
                                 hoverChanged: { isHovering in
                                     handlers.hoverChanged(node, isHovering)
                                 },
                                 activate: {
                                     handlers.activate(node)
                                 })
                                 .id(node.id)
                                 .onGeometryChange(for: CGRect.self) { proxy in
                                     proxy.frame(in: .global)
                                 } action: { frame in
                                     handlers.frameChanged(node, frame)
                                 }
            }
        }
    }
}
