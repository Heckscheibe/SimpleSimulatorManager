//
//  MenuPanelViewModel.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 04.09.26.
//

import Foundation
import Observation

/// One level of the panel: the rows to show, and the title of the submenu they came from.
struct MenuPanelLevel {
    /// `nil` at the top level, where there is nothing to go back to.
    let title: String?
    let nodes: [MenuNode]
    /// How many submenus deep this level is. `0` is the top level.
    let depth: Int
}

/// Drill-down state for the menu bar panel.
///
/// The path is kept as identifiers rather than as nodes, so the level on screen is resolved against
/// a freshly built tree on every render. That is what lets an app installed while the panel is open
/// appear in it, instead of the panel being frozen at whatever the tree looked like when it opened.
@MainActor
@Observable
final class MenuPanelViewModel {
    private(set) var pathIdentifiers: [String] = []

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

    func enter(_ node: MenuNode) {
        guard node.isSubmenu, node.isEnabled else {
            return
        }

        pathIdentifiers.append(node.id)
        node.onEnter?()
    }

    /// Goes back one level. Takes the resolved level so a path that outlived its nodes is trimmed
    /// to what is actually on screen instead of unwinding steps the user never sees.
    func leave(from level: MenuPanelLevel) {
        pathIdentifiers = Array(pathIdentifiers.prefix(max(0, level.depth - 1)))
    }

    /// Reopening the panel starts at the top level, the way reopening a menu does.
    func reset() {
        pathIdentifiers.removeAll()
    }
}
