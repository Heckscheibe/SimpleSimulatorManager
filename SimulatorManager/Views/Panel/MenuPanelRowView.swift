//
//  MenuPanelRowView.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 04.09.26.
//

import SwiftUI

/// Renders one ``MenuNode``.
///
/// Presentation only: it decides nothing about what a row does, it just draws the node it is given
/// and reports a click.
struct MenuPanelRowView: View {
    let node: MenuNode
    let activate: () -> Void

    @State private var isHovering = false

    var body: some View {
        switch node.kind {
        case .divider:
            Divider()
                .padding(.horizontal, MenuPanelStyle.horizontalInset)
                .padding(.vertical, MenuPanelStyle.dividerVerticalPadding)
        case .sectionHeader, .informational:
            labelContent
                .foregroundStyle(.secondary)
                .padding(.horizontal, MenuPanelStyle.rowHorizontalPadding)
                .padding(.vertical, MenuPanelStyle.rowVerticalPadding)
                .padding(.horizontal, MenuPanelStyle.horizontalInset)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .action, .submenu:
            interactiveRow
        }
    }
}

private extension MenuPanelRowView {
    var isHighlighted: Bool {
        isHovering && node.isEnabled
    }

    var interactiveRow: some View {
        HStack(spacing: 6) {
            labelContent

            Spacer(minLength: 4)

            if node.isSubmenu {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isHighlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            }
        }
        .padding(.horizontal, MenuPanelStyle.rowHorizontalPadding)
        .padding(.vertical, MenuPanelStyle.rowVerticalPadding)
        .frame(minHeight: MenuPanelStyle.rowMinimumHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(foregroundStyle)
        .background(highlight)
        .padding(.horizontal, MenuPanelStyle.horizontalInset)
        .opacity(node.isEnabled ? 1 : MenuPanelStyle.disabledOpacity)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture {
            guard node.isEnabled else {
                return
            }

            activate()
        }
    }

    var labelContent: some View {
        HStack(spacing: 6) {
            if let iconName = node.iconName {
                Image(systemName: iconName)
                    .frame(width: MenuPanelStyle.iconWidth)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(node.title)
                    .font(MenuPanelStyle.titleFont)

                if let subtitle = node.subtitle {
                    Text(subtitle)
                        .font(MenuPanelStyle.subtitleFont)
                        .foregroundStyle(isHighlighted ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                }
            }
            .lineLimit(1)
            .truncationMode(.middle)
        }
    }

    var foregroundStyle: AnyShapeStyle {
        if isHighlighted {
            return AnyShapeStyle(.white)
        }

        // Destructive rows are tinted rather than left to look like every other row: the panel has
        // no `NSMenu` behind it to mark them, and erasing a simulator cannot be undone.
        return node.isDestructive ? AnyShapeStyle(Color.red) : AnyShapeStyle(Color.primary)
    }

    @ViewBuilder
    var highlight: some View {
        if isHighlighted {
            RoundedRectangle(cornerRadius: MenuPanelStyle.rowCornerRadius, style: .continuous)
                .fill(Color.accentColor)
        }
    }
}
