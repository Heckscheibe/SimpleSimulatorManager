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
    /// Selection lives in the view model, so hover and the arrow keys drive one highlight rather
    /// than two that can disagree.
    let isSelected: Bool
    let isAwaitingConfirmation: Bool
    let hoverChanged: (Bool) -> Void
    let activate: () -> Void

    var body: some View {
        switch node.kind {
        case .divider:
            Divider()
                .padding(.horizontal, MenuPanelStyle.horizontalInset)
                .padding(.vertical, MenuPanelStyle.dividerVerticalPadding)
                // A separator is a drawing, not something to land on.
                .accessibilityHidden(true)
        case .sectionHeader, .informational:
            labelContent
                .foregroundStyle(.secondary)
                .padding(.horizontal, MenuPanelStyle.rowHorizontalPadding)
                .padding(.vertical, MenuPanelStyle.rowVerticalPadding)
                .padding(.horizontal, MenuPanelStyle.horizontalInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(node.kind.isSectionHeader ? .isHeader : .isStaticText)
        case .action, .submenu:
            interactiveRow
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(node.accessibilityLabel)
                .accessibilityAddTraits(accessibilityTraits)
                .accessibilityHint(node.accessibilityHint(isAwaitingConfirmation: isAwaitingConfirmation))
                .accessibilityAction {
                    guard node.isEnabled else {
                        return
                    }

                    activate()
                }
        }
    }
}

private extension MenuPanelRowView {
    var isHighlighted: Bool {
        isSelected && node.isEnabled
    }

    var interactiveRow: some View {
        HStack(spacing: 6) {
            labelContent

            Spacer(minLength: 4)

            if isAwaitingConfirmation {
                Text("press ↩ again")
                    .font(MenuPanelStyle.subtitleFont)
                    .foregroundStyle(isHighlighted ? AnyShapeStyle(.white) : AnyShapeStyle(Color.red))
            }

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
        .onHover(perform: hoverChanged)
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
            .lineLimit(wrapsText ? nil : 1)
            .truncationMode(.middle)
            // Informational rows carry sentences rather than names, and a sentence truncated in the
            // middle tells the user nothing — least of all when the sentence is explaining why an
            // irreversible deletion is on offer. Everything else stays on one line, the way a menu
            // item does.
            .fixedSize(horizontal: false, vertical: wrapsText)
        }
    }

    var wrapsText: Bool {
        if case .informational = node.kind {
            return true
        }

        return false
    }

    var accessibilityTraits: AccessibilityTraits {
        var traits: AccessibilityTraits = node.isSubmenu ? [] : [.isButton]

        if isSelected {
            traits.insert(.isSelected)
        }

        return traits
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
