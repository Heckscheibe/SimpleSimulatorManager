//
//  MenuFlyoutContentView.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 06.09.26.
//

import SwiftUI

/// One open submenu, drawn in its own window beside the panel.
///
/// It has to draw its own background and corner: the panel gets both from the system, and a flyout
/// is a borderless window that gets nothing.
struct MenuFlyoutContentView: View {
    let nodes: [MenuNode]
    let handlers: MenuRowHandlers
    /// Reports the size the flyout wants. The window is created before its contents have ever been
    /// laid out, and a `ScrollView` has no intrinsic height for it to have been sized from, so the
    /// measurement has to travel back out rather than being read off the view.
    let sizeChanged: (CGSize) -> Void

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            MenuNodeRowsView(nodes: nodes, handlers: handlers)
                .padding(.vertical, MenuPanelStyle.listVerticalPadding)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    contentHeight = height
                }
        }
        .frame(width: MenuPanelStyle.width, height: height)
        .scrollBounceBehavior(.basedOnSize)
        .background(.regularMaterial)
        .clipShape(shape)
        .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 1))
        // Deliberately without `initial:`, so nothing is reported until the rows have actually been
        // measured — a window ordered in at a placeholder height would visibly snap to its real one.
        .onChange(of: height) { _, height in
            sizeChanged(CGSize(width: MenuPanelStyle.width, height: height))
        }
    }
}

private extension MenuFlyoutContentView {
    /// Capped like the panel's list, for the same reason: a device with two dozen apps would
    /// otherwise open a submenu taller than the screen.
    var height: CGFloat {
        min(max(contentHeight, MenuPanelStyle.rowMinimumHeight), MenuPanelStyle.maximumListHeight)
    }

    var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: MenuPanelStyle.flyoutCornerRadius, style: .continuous)
    }
}
