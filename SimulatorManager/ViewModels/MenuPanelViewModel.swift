//
//  MenuPanelViewModel.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 04.09.26.
//

import Foundation
import Observation

// MARK: - Supporting types

/// One level of the panel: the rows to show, and the title of the submenu they came from.
struct MenuPanelLevel {
    /// `nil` at the top level, where there is nothing to go back to.
    let title: String?
    let nodes: [MenuNode]
    /// How many submenus deep this level is. `0` is the top level.
    let depth: Int
}

enum MenuPanelMoveDirection {
    case up
    case down
}

/// Which of a row's actions to run. `NSMenu` had no equivalent: reaching an app's App Package meant
/// opening its submenu, and a modifier gets there in one keystroke instead.
enum MenuPanelActionKind: Equatable {
    case primary
    case secondary(index: Int)
}

enum MenuPanelActivationOutcome: Equatable {
    /// Nothing to do: the row is disabled, or has no action of the requested kind.
    case none
    /// Drilled into a submenu.
    case entered
    /// The action ran. The panel should close, the way picking a menu item closed the menu.
    case performed
    /// A destructive row is now waiting for a confirming second <kbd>↩</kbd>.
    case awaitingConfirmation
}

// MARK: - View model

/// Drill-down and keyboard state for the menu bar panel.
///
/// The path is kept as identifiers rather than as nodes, so the level on screen is resolved against
/// a freshly built tree on every render. That is what lets an app installed while the panel is open
/// appear in it, instead of the panel being frozen at whatever the tree looked like when it opened.
@MainActor
@Observable
final class MenuPanelViewModel {
    private(set) var pathIdentifiers: [String] = []
    /// The highlighted row, or `nil` when nothing is selected. Mouse hover and the arrow keys drive
    /// the same value, so the highlight can never appear in two places at once.
    private(set) var selectedIdentifier: String?
    /// A destructive row waiting for its confirming second <kbd>↩</kbd>.
    private(set) var pendingDestructiveIdentifier: String?

    /// Resolves the level currently on screen.
    ///
    /// If a level disappeared while the panel was open — its simulator was erased, its app deleted
    /// — resolution stops at the deepest level that still exists rather than showing nothing.
    func level(in rootNodes: [MenuNode]) -> MenuPanelLevel {
        var nodes = rootNodes
        var title: String?
        var depth = 0

        for identifier in pathIdentifiers {
            guard let match = nodes.first(where: { $0.id == identifier }), match.isSubmenu else {
                break
            }

            nodes = match.children
            title = match.title
            depth += 1
        }

        return MenuPanelLevel(title: title, nodes: nodes, depth: depth)
    }

    /// Reopening the panel starts at the top level with nothing selected, the way reopening a menu
    /// does.
    func reset() {
        pathIdentifiers.removeAll()
        selectedIdentifier = nil
        pendingDestructiveIdentifier = nil
    }
}

// MARK: - Navigation

extension MenuPanelViewModel {
    func enter(_ node: MenuNode) {
        guard node.isSubmenu, node.isEnabled else {
            return
        }

        pathIdentifiers.append(node.id)
        // A new level starts unselected, so no row — least of all a destructive one — is sitting
        // under the first Return the user presses.
        selectedIdentifier = nil
        cancelPendingConfirmation()
        node.onEnter?()
    }

    /// Goes back one level. Takes the resolved level so a path that outlived its nodes is trimmed
    /// to what is actually on screen instead of unwinding steps the user never sees.
    func leave(from level: MenuPanelLevel) {
        let remainingDepth = max(0, level.depth - 1)
        // Coming back out puts the highlight on the row that was entered, so → then ← returns the
        // user exactly where they were.
        let enteredIdentifier = pathIdentifiers.indices.contains(remainingDepth)
            ? pathIdentifiers[remainingDepth]
            : nil

        pathIdentifiers = Array(pathIdentifiers.prefix(remainingDepth))
        selectedIdentifier = enteredIdentifier
        cancelPendingConfirmation()
    }
}

// MARK: - Selection

extension MenuPanelViewModel {
    func isSelected(_ node: MenuNode) -> Bool {
        node.id == selectedIdentifier
    }

    func isAwaitingConfirmation(_ node: MenuNode) -> Bool {
        node.id == pendingDestructiveIdentifier
    }

    func selectedNode(in level: MenuPanelLevel) -> MenuNode? {
        guard let selectedIdentifier else {
            return nil
        }

        return level.nodes.first { $0.id == selectedIdentifier && $0.isSelectable }
    }

    /// Moves to the next or previous selectable row, wrapping at both ends.
    ///
    /// Section headers, informational text, dividers and disabled rows are skipped entirely, the
    /// way `NSMenu` skipped them.
    func moveSelection(_ direction: MenuPanelMoveDirection, in level: MenuPanelLevel) {
        cancelPendingConfirmation()

        let selectableNodes = level.nodes.filter(\.isSelectable)

        guard !selectableNodes.isEmpty else {
            selectedIdentifier = nil

            return
        }
        guard let currentIdentifier = selectedIdentifier,
              let currentIndex = selectableNodes.firstIndex(where: { $0.id == currentIdentifier }) else {
            selectedIdentifier = direction == .down ? selectableNodes.first?.id : selectableNodes.last?.id

            return
        }

        let offset = direction == .down ? 1 : -1
        let nextIndex = (currentIndex + offset + selectableNodes.count) % selectableNodes.count

        selectedIdentifier = selectableNodes[nextIndex].id
    }

    /// Mouse hover and keyboard selection are the same state, so the highlight follows the pointer
    /// rather than appearing alongside a second one.
    func select(_ node: MenuNode) {
        guard node.isSelectable else {
            return
        }

        if node.id != selectedIdentifier {
            cancelPendingConfirmation()
        }

        selectedIdentifier = node.id
    }

    func clearSelection(ifSelected node: MenuNode) {
        guard selectedIdentifier == node.id else {
            return
        }

        selectedIdentifier = nil
        cancelPendingConfirmation()
    }

    func cancelPendingConfirmation() {
        pendingDestructiveIdentifier = nil
    }
}

// MARK: - Activation

extension MenuPanelViewModel {
    /// Activation from the keyboard, where destructive rows are guarded.
    @discardableResult
    func activateFromKeyboard(_ node: MenuNode, kind: MenuPanelActionKind = .primary) -> MenuPanelActivationOutcome {
        activate(node, kind: kind, guardsDestructiveActions: true)
    }

    /// Activation from a click, which behaves exactly as it did in the menu: one click runs the
    /// item. The guard exists for keystrokes landing in a panel the user may have just opened over
    /// their pointer, not for a deliberate click.
    @discardableResult
    func activateFromMouse(_ node: MenuNode) -> MenuPanelActivationOutcome {
        activate(node, kind: .primary, guardsDestructiveActions: false)
    }
}

private extension MenuPanelViewModel {
    func activate(
        _ node: MenuNode,
        kind: MenuPanelActionKind,
        guardsDestructiveActions: Bool
    ) -> MenuPanelActivationOutcome {
        guard node.isEnabled else {
            return .none
        }

        // Return on a submenu drills in rather than activating, matching `NSMenu`.
        if node.isSubmenu, kind == .primary {
            enter(node)

            return .entered
        }
        guard let action = action(for: node, kind: kind) else {
            return .none
        }

        // Erasing a simulator cannot be undone, and a panel that opens under the pointer makes a
        // stray Return far too cheap — so a destructive row costs two.
        if guardsDestructiveActions, node.isDestructive, pendingDestructiveIdentifier != node.id {
            pendingDestructiveIdentifier = node.id

            return .awaitingConfirmation
        }

        cancelPendingConfirmation()
        action.perform()

        return .performed
    }

    func action(for node: MenuNode, kind: MenuPanelActionKind) -> MenuActionItem? {
        switch kind {
        case .primary:
            return node.primaryAction
        case let .secondary(index):
            let secondaryActions = node.secondaryActions

            // A row without that secondary action ignores the shortcut rather than falling back to
            // the primary one: silently opening the wrong folder is worse than doing nothing.
            guard secondaryActions.indices.contains(index) else {
                return nil
            }

            return secondaryActions[index]
        }
    }
}
