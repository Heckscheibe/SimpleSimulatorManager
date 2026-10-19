//
//  MenuPanelRowEquatableTests.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 19.10.26.
//

import Foundation
import Testing
@testable import SimulatorManager

/// A hover changes the highlight of two rows. Rows compare by what they draw, so SwiftUI can skip
/// every other row of every open level instead of redrawing them all.
@Suite("MenuPanelRowView equality")
@MainActor
struct MenuPanelRowEquatableTests {
    @Test("A row rebuilt with fresh closures but nothing new to draw is unchanged")
    func freshClosuresAreNotAChange() {
        let node = Self.submenu(title: "iPhone 16 Pro")

        #expect(Self.row(node) == Self.row(node))
    }

    @Test("Gaining or losing the highlight is a change")
    func highlightIsAChange() {
        let node = Self.submenu(title: "iPhone 16 Pro")

        #expect(Self.row(node, isSelected: true) != Self.row(node, isSelected: false))
    }

    @Test("Waiting for a confirming Return is a change")
    func pendingConfirmationIsAChange() {
        let node = Self.submenu(title: "iPhone 16 Pro")

        #expect(Self.row(node, isAwaitingConfirmation: true) != Self.row(node))
    }

    @Test("A row whose text changed is a change, even under the same identifier")
    func changedTitleIsAChange() {
        #expect(Self.row(Self.submenu(title: "iPhone 16 Pro")) != Self.row(Self.submenu(title: "iPhone 16 Pro Max")))
    }

    @Test("A row that was disabled, or gained an action, is a change")
    func changedStateIsAChange() {
        let enabled = MenuNode.action(id: "erase", title: "Erase", isDestructive: true) {}
        let disabled = MenuNode.action(id: "erase", title: "Erase", isEnabled: false, isDestructive: true) {}

        #expect(Self.row(enabled) != Self.row(disabled))

        let oneAction = MenuNode.action(id: "app", title: "App", actions: [MenuActionItem(title: "Open") {}])
        let twoActions = MenuNode.action(id: "app",
                                         title: "App",
                                         actions: [MenuActionItem(title: "Open") {}, MenuActionItem(title: "Reveal") {}])

        #expect(Self.row(oneAction) != Self.row(twoActions))
    }
}

@MainActor
private extension MenuPanelRowEquatableTests {
    static func submenu(title: String) -> MenuNode {
        .submenu(id: "device", title: title, children: [.action(id: "device.child", title: "Child") {}])
    }

    static func row(_ node: MenuNode, isSelected: Bool = false, isAwaitingConfirmation: Bool = false) -> MenuPanelRowView {
        MenuPanelRowView(node: node,
                         isSelected: isSelected,
                         isAwaitingConfirmation: isAwaitingConfirmation,
                         hoverChanged: { _ in },
                         activate: {})
    }
}
