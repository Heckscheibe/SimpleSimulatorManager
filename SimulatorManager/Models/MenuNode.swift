//
//  MenuNode.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 04.09.26.
//

import Foundation

// MARK: - Action

/// One thing a menu row can do.
struct MenuActionItem {
    let title: String
    let perform: @MainActor () -> Void
}

// MARK: - Node

/// A single row of the menu, described as data rather than as a view.
///
/// A panel cannot borrow what `NSMenu` supplied for free. Arrow-key selection has to know the
/// ordered list of rows at the level currently on screen, and search has to know which rows exist
/// at all — neither is answerable while the menu exists only as view builders. Describing it as a
/// tree puts selection, drill-down and filtering on one structure instead of scattering them
/// across ten views, and keeps the views presentation-only.
struct MenuNode: Identifiable {
    enum Kind {
        /// A row that only performs its action.
        case action
        /// A row that opens a deeper level. It may still carry actions of its own: an app row's
        /// children are its folder actions, and those stay reachable with a modifier.
        case submenu([MenuNode])
        /// A non-interactive group label, such as "Recent Apps".
        case sectionHeader
        /// Non-interactive status text, such as "No apps installed".
        case informational
        case divider
    }

    /// Stable across rebuilds because it is derived from the thing the row represents — a device
    /// UDID, a bundle identifier — and never from a position in an array. Refreshing one device
    /// republishes the whole devices array, and selection must not jump because of it.
    let id: String
    let title: String
    let subtitle: String?
    let iconName: String?
    let isEnabled: Bool
    /// Erase Simulator, Reset All Simulators and the cleanup deletions. The panel guards these
    /// against being triggered by accident from the keyboard.
    let isDestructive: Bool
    /// What the row can do, primary action first. Empty for headers, informational rows, dividers,
    /// and for submenus that only group other rows.
    let actions: [MenuActionItem]
    /// Work to start when this submenu is opened. The cleanup scan is expensive and is deliberately
    /// deferred until the user asks for it, exactly as the `.task` on the old cleanup submenu did.
    let onEnter: (@MainActor () -> Void)?
    let kind: Kind
}

// MARK: - Convenience

extension MenuNode.Kind {
    var isSectionHeader: Bool {
        if case .sectionHeader = self {
            return true
        }

        return false
    }
}

extension MenuNode {
    var primaryAction: MenuActionItem? {
        actions.first
    }

    /// Reachable with a modifier without drilling into the row.
    var secondaryActions: [MenuActionItem] {
        Array(actions.dropFirst())
    }

    var children: [MenuNode] {
        guard case let .submenu(children) = kind else {
            return []
        }

        return children
    }

    /// Whether the keyboard may land on this row. Headers, informational text and dividers are
    /// skipped over entirely, and so are disabled rows — matching how `NSMenu` behaved.
    var isSelectable: Bool {
        guard isEnabled else {
            return false
        }

        switch kind {
        case .action, .submenu:
            return true
        case .sectionHeader, .informational, .divider:
            return false
        }
    }

    var isSubmenu: Bool {
        if case .submenu = kind {
            return true
        }

        return false
    }
}

// MARK: - Accessibility

extension MenuNode {
    /// `NSMenu` announced its items for free. A panel row is a stack of `Text`s, so the label is
    /// assembled explicitly — and an app hit has to name its device, because "Documents Folder" is
    /// useless when the same app is installed on eight simulators.
    var accessibilityLabel: String {
        var components = [title]

        if let subtitle {
            components.append(subtitle)
        }

        if isDestructive {
            components.append("destructive")
        }

        if !isEnabled {
            components.append("dimmed")
        }

        return components.joined(separator: ", ")
    }

    /// A confirmation the user cannot perceive is not a confirmation, so the pending state is
    /// announced rather than only tinted.
    func accessibilityHint(isAwaitingConfirmation: Bool) -> String {
        if isAwaitingConfirmation {
            return "Press Return again to confirm"
        }

        return isSubmenu ? "Opens a submenu" : ""
    }
}

// MARK: - Factories

extension MenuNode {
    static func action(
        id: String,
        title: String,
        subtitle: String? = nil,
        iconName: String? = nil,
        isEnabled: Bool = true,
        isDestructive: Bool = false,
        actions: [MenuActionItem]
    ) -> MenuNode {
        MenuNode(id: id,
                 title: title,
                 subtitle: subtitle,
                 iconName: iconName,
                 isEnabled: isEnabled,
                 isDestructive: isDestructive,
                 actions: actions,
                 onEnter: nil,
                 kind: Kind.action)
    }

    static func submenu(
        id: String,
        title: String,
        subtitle: String? = nil,
        iconName: String? = nil,
        isEnabled: Bool = true,
        actions: [MenuActionItem] = [],
        onEnter: (@MainActor () -> Void)? = nil,
        children: [MenuNode]
    ) -> MenuNode {
        MenuNode(id: id,
                 title: title,
                 subtitle: subtitle,
                 iconName: iconName,
                 isEnabled: isEnabled,
                 isDestructive: false,
                 actions: actions,
                 onEnter: onEnter,
                 kind: Kind.submenu(children))
    }

    /// A row with exactly one action, which is almost every action row.
    static func action(
        id: String,
        title: String,
        isEnabled: Bool = true,
        isDestructive: Bool = false,
        perform: @escaping @MainActor () -> Void
    ) -> MenuNode {
        let action = MenuActionItem(title: title, perform: perform)

        return .action(id: id,
                       title: title,
                       isEnabled: isEnabled,
                       isDestructive: isDestructive,
                       actions: [action])
    }

    static func sectionHeader(id: String, title: String) -> MenuNode {
        MenuNode(id: id,
                 title: title,
                 subtitle: nil,
                 iconName: nil,
                 isEnabled: true,
                 isDestructive: false,
                 actions: [],
                 onEnter: nil,
                 kind: Kind.sectionHeader)
    }

    static func informational(id: String, title: String) -> MenuNode {
        MenuNode(id: id,
                 title: title,
                 subtitle: nil,
                 iconName: nil,
                 isEnabled: true,
                 isDestructive: false,
                 actions: [],
                 onEnter: nil,
                 kind: Kind.informational)
    }

    static func divider(id: String) -> MenuNode {
        MenuNode(id: id,
                 title: "",
                 subtitle: nil,
                 iconName: nil,
                 isEnabled: false,
                 isDestructive: false,
                 actions: [],
                 onEnter: nil,
                 kind: Kind.divider)
    }

    /// Turns an action's fixed English title into an identifier component, so a row built from an
    /// action list still gets an identity derived from what it does rather than from its position.
    static func identifierComponent(from title: String) -> String {
        title
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
}
