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
    /// Reports a size the window could not have worked out for itself — a level that grew or shrank
    /// while it was open, and the height of a level too tall to show whole.
    let sizeChanged: (CGSize) -> Void

    /// `nil` until the rows have been laid out, which is a state in its own right rather than a
    /// height of zero: while it holds, the view imposes no height at all, so the window can ask the
    /// hosting view how big it wants to be and show it in the same turn.
    @State private var contentHeight: CGFloat?

    var body: some View {
        content
            .background(.regularMaterial)
            .clipShape(shape)
            .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 1))
            .onChange(of: contentHeight) { _, measured in
                guard let measured else {
                    return
                }

                sizeChanged(CGSize(width: MenuPanelStyle.width, height: Self.height(for: measured)))
            }
    }
}

private extension MenuFlyoutContentView {
    /// Two shapes, for one reason: **a flyout has to be sized and shown in a single turn.**
    ///
    /// A `ScrollView` has no intrinsic height, so a view built around one can only be measured by
    /// laying it out, reporting its size back out, and being shown on a later pass — and those
    /// passes are exactly the lag between the pointer landing on a row and its submenu appearing.
    /// Before the rows have been measured there is no scroll view and no imposed height, so
    /// `fittingSize` on the hosting view answers the question immediately. The scroll view arrives
    /// with the measurement, which is the only point at which it has anything to do.
    @ViewBuilder
    var content: some View {
        if let contentHeight {
            ScrollView {
                rows
            }
            .frame(width: MenuPanelStyle.width, height: Self.height(for: contentHeight))
            .scrollBounceBehavior(.basedOnSize)
        } else {
            rows
                .frame(width: MenuPanelStyle.width)
        }
    }

    var rows: some View {
        MenuNodeRowsView(nodes: nodes, handlers: contentHeight == nil ? handlers.withoutRowFrames() : handlers)
            .padding(.vertical, MenuPanelStyle.listVerticalPadding)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                contentHeight = height
            }
    }

    /// Capped like the panel's list, for the same reason: a device with two dozen apps would
    /// otherwise open a submenu taller than the screen.
    static func height(for contentHeight: CGFloat) -> CGFloat {
        min(max(contentHeight, MenuPanelStyle.rowMinimumHeight), MenuPanelStyle.maximumListHeight)
    }

    var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: MenuPanelStyle.flyoutCornerRadius, style: .continuous)
    }
}
