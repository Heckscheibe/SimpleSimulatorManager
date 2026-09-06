//
//  MenuPanelFlyoutChainTests.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 06.09.26.
//

import Foundation
import Testing
@testable import SimulatorManager

/// The open path is the flyout chain. Drill-down only ever appended to it and popped the last entry;
/// a pointer can land anywhere in the chain at once, so the same path now has to be truncated from
/// the middle — and every level of it has to stay resolvable, because each one is a window.
@Suite("Menu panel flyout chain")
@MainActor
struct MenuPanelFlyoutChainTests {
    // MARK: - Levels

    @Test("Every open level is resolved, root first")
    func openLevelsAreResolvedInOrder() {
        let viewModel = MenuPanelViewModel()
        let nodes = Self.tree()

        viewModel.openFlyout(for: Self.node("device-type", in: nodes), atDepth: 0)
        viewModel.openFlyout(for: Self.node("device", in: nodes), atDepth: 1)

        let levels = viewModel.levels(in: nodes)

        #expect(levels.count == 3)
        #expect(levels.map(\.depth) == [0, 1, 2])
        #expect(levels[1].title == "iPhone 17 Pro")
        #expect(levels[2].nodes.map(\.id) == ["app"])
    }

    @Test("A level whose nodes disappeared ends the chain instead of leaving a window with nothing in it")
    func vanishedLevelsAreDropped() {
        let viewModel = MenuPanelViewModel()
        let nodes = Self.tree()

        viewModel.openFlyout(for: Self.node("device-type", in: nodes), atDepth: 0)
        viewModel.openFlyout(for: Self.node("device", in: nodes), atDepth: 1)

        // The simulator was erased while its submenus were open: the device type it sat under is
        // still there, the device is not.
        let pruned = [MenuNode.submenu(id: "device-type", title: "iPhone 17 Pro", children: [])]

        #expect(viewModel.levels(in: pruned).count == 2)
        #expect(viewModel.level(in: pruned).depth == 1)

        // And with the whole branch gone, the chain is back to the panel alone.
        let empty = [MenuNode.action(id: "settings", title: "Settings") {}]

        #expect(viewModel.levels(in: empty).count == 1)
    }

    // MARK: - Opening

    @Test("Opening a submenu from a shallower row replaces the chain rather than extending it")
    func openingFromAShallowerRowTruncatesTheChain() {
        let viewModel = MenuPanelViewModel()
        let nodes = Self.tree()

        viewModel.openFlyout(for: Self.node("device-type", in: nodes), atDepth: 0)
        viewModel.openFlyout(for: Self.node("device", in: nodes), atDepth: 1)
        #expect(viewModel.pathIdentifiers == ["device-type", "device"])

        // The pointer goes back up to the panel and lands on a different device type. Both flyouts
        // belong to the branch it just left.
        viewModel.openFlyout(for: Self.node("other-device-type", in: nodes), atDepth: 0)

        #expect(viewModel.pathIdentifiers == ["other-device-type"])
    }

    @Test("Re-entering the row a flyout is already open on changes nothing")
    func reopeningAnOpenRowIsIgnored() {
        let counter = OnEnterCounter()
        let node = MenuNode.submenu(id: "cleanup",
                                    title: "Clean Up",
                                    onEnter: { counter.increment() },
                                    children: [])
        let viewModel = MenuPanelViewModel()

        viewModel.openFlyout(for: node, atDepth: 0)
        viewModel.openFlyout(for: node, atDepth: 0)

        // The cleanup scan is deliberately deferred until its submenu is opened, and the pointer
        // wandering back onto the row must not start it again.
        #expect(counter.count == 1)
        #expect(viewModel.pathIdentifiers == ["cleanup"])
    }

    @Test("A row that is not a submenu closes the flyouts beside its level")
    func anOrdinaryRowClosesTheChain() {
        let viewModel = MenuPanelViewModel()
        let nodes = Self.tree()

        viewModel.openFlyout(for: Self.node("device-type", in: nodes), atDepth: 0)
        viewModel.openFlyout(for: MenuNode.action(id: "settings", title: "Settings") {}, atDepth: 0)

        #expect(viewModel.pathIdentifiers.isEmpty)
    }

    @Test("Closing keeps the levels above the one asked for")
    func closingTrimsToTheGivenDepth() {
        let viewModel = MenuPanelViewModel()
        let nodes = Self.tree()

        viewModel.openFlyout(for: Self.node("device-type", in: nodes), atDepth: 0)
        viewModel.openFlyout(for: Self.node("device", in: nodes), atDepth: 1)

        viewModel.closeFlyouts(deeperThan: 1)

        #expect(viewModel.pathIdentifiers == ["device-type"])
    }

    // MARK: - Highlighting

    @Test("A row with a flyout open stays highlighted")
    func openRowsStayHighlighted() {
        let viewModel = MenuPanelViewModel()
        let nodes = Self.tree()
        let deviceType = Self.node("device-type", in: nodes)

        viewModel.openFlyout(for: deviceType, atDepth: 0)

        // Opening clears the keyboard selection, so without this the row the pointer is sitting on
        // would go dark the moment its submenu appeared.
        #expect(viewModel.selectedIdentifier == nil)
        #expect(viewModel.isOnOpenPath(deviceType))
        #expect(viewModel.isHighlighted(deviceType))
    }

    @Test("The row the pointer moves to takes the highlight from the row whose flyout is open")
    func theHighlightFollowsThePointer() {
        let viewModel = MenuPanelViewModel()
        let nodes = Self.tree()
        let deviceType = Self.node("device-type", in: nodes)
        let other = Self.node("other-device-type", in: nodes)

        viewModel.openFlyout(for: deviceType, atDepth: 0)
        // The pointer moves to the next row. Its flyout has not replaced the open one yet — a flyout
        // outlives the pointer leaving the row that opened it.
        viewModel.select(other)

        #expect(viewModel.isHighlighted(other))
        // Two rows lit at once is what a menu never showed, and what makes the swap look broken.
        #expect(!viewModel.isHighlighted(deviceType))
    }

    // MARK: - Search

    @Test("Typing closes the whole chain")
    func searchingClosesTheChain() {
        let viewModel = MenuPanelViewModel()
        let nodes = Self.tree()
        let results = [MenuNode.action(id: "hit", title: "Test App") {}]

        viewModel.openFlyout(for: Self.node("device-type", in: nodes), atDepth: 0)
        viewModel.openFlyout(for: Self.node("device", in: nodes), atDepth: 1)

        // Results are a flat list, so the flyouts are hanging off rows that are no longer on screen.
        viewModel.applyQueryChange(isSearching: true, resultLevel: MenuPanelLevel(title: nil, nodes: results, depth: 0))

        #expect(viewModel.pathIdentifiers.isEmpty)
        #expect(viewModel.selectedIdentifier == "hit")
    }
}

// MARK: - Helpers

/// Counts how often a submenu's deferred work was started.
@MainActor
private final class OnEnterCounter {
    private(set) var count = 0

    func increment() {
        count += 1
    }
}

private extension MenuPanelFlyoutChainTests {
    /// A slice of the real shape: device type → device → app.
    static func tree() -> [MenuNode] {
        let app = MenuNode.submenu(id: "app", title: "Test App", children: [])
        let device = MenuNode.submenu(id: "device", title: "iPhone 17 Pro", children: [app])
        let deviceType = MenuNode.submenu(id: "device-type", title: "iPhone 17 Pro", children: [device])
        let otherDeviceType = MenuNode.submenu(id: "other-device-type", title: "iPad Pro", children: [])

        return [deviceType, otherDeviceType]
    }

    static func node(_ identifier: String, in nodes: [MenuNode]) -> MenuNode {
        // Force-unwrapped deliberately: a missing node means the fixture is wrong, and a fallback
        // would turn that into a passing test.
        nodes.compactMap { $0.descendant(withID: identifier) }[0]
    }
}
