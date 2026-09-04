//
//  MenuPanelViewModelTests.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 04.09.26.
//

import Foundation
import Testing
@testable import SimulatorManager

/// Keyboard navigation was free while the menu was an `NSMenu`. It is hand-written now, so every
/// rule it used to get from AppKit is pinned down here.
@Suite("MenuPanelViewModel Tests")
@MainActor
struct MenuPanelViewModelTests {
    // MARK: - Movement

    @Test("Moving down skips headers, informational rows and dividers")
    func movementSkipsNonSelectableRows() {
        let viewModel = MenuPanelViewModel()
        let level = makeLevel(mixedNodes())

        viewModel.moveSelection(.down, in: level)
        #expect(viewModel.selectedIdentifier == "first")

        viewModel.moveSelection(.down, in: level)
        #expect(viewModel.selectedIdentifier == "second")

        viewModel.moveSelection(.down, in: level)
        #expect(viewModel.selectedIdentifier == "third")
    }

    @Test("Moving down past the last row wraps to the first, and up past the first wraps to the last")
    func movementWraps() {
        let viewModel = MenuPanelViewModel()
        let level = makeLevel(mixedNodes())

        viewModel.moveSelection(.up, in: level)
        #expect(viewModel.selectedIdentifier == "third")

        viewModel.moveSelection(.down, in: level)
        #expect(viewModel.selectedIdentifier == "first")

        viewModel.moveSelection(.up, in: level)
        #expect(viewModel.selectedIdentifier == "third")
    }

    @Test("Disabled rows cannot be selected")
    func disabledRowsAreSkipped() {
        let viewModel = MenuPanelViewModel()
        let level = makeLevel([
            makeAction(id: "enabled"),
            makeAction(id: "disabled", isEnabled: false),
            makeAction(id: "also-enabled")
        ])

        viewModel.moveSelection(.down, in: level)
        viewModel.moveSelection(.down, in: level)

        #expect(viewModel.selectedIdentifier == "also-enabled")
    }

    @Test("A level with nothing selectable leaves the selection empty")
    func movementInALevelWithoutSelectableRows() {
        let viewModel = MenuPanelViewModel()
        let level = makeLevel([.sectionHeader(id: "header", title: "Header"), .divider(id: "divider")])

        viewModel.moveSelection(.down, in: level)
        #expect(viewModel.selectedIdentifier == nil)

        viewModel.moveSelection(.up, in: level)
        #expect(viewModel.selectedIdentifier == nil)
    }

    @Test("A level with exactly one selectable row stays on it")
    func movementWithASingleSelectableRow() {
        let viewModel = MenuPanelViewModel()
        let level = makeLevel([.divider(id: "divider"), makeAction(id: "only")])

        viewModel.moveSelection(.down, in: level)
        #expect(viewModel.selectedIdentifier == "only")

        viewModel.moveSelection(.down, in: level)
        #expect(viewModel.selectedIdentifier == "only")

        viewModel.moveSelection(.up, in: level)
        #expect(viewModel.selectedIdentifier == "only")
    }

    // MARK: - Drill-down

    @Test("Entering a submenu starts unselected, and leaving restores the row that was entered")
    func enteringAndLeavingRestoresSelection() {
        let child = makeAction(id: "child")
        let parent = MenuNode.submenu(id: "parent", title: "Parent", children: [child])
        let viewModel = MenuPanelViewModel()
        let root = makeLevel([makeAction(id: "before"), parent])

        viewModel.select(parent)
        viewModel.enter(parent)

        let childLevel = viewModel.level(in: root.nodes)
        #expect(viewModel.selectedIdentifier == nil)
        #expect(childLevel.depth == 1)
        #expect(childLevel.title == "Parent")
        #expect(childLevel.nodes.identifiers == ["child"])

        viewModel.moveSelection(.down, in: childLevel)
        #expect(viewModel.selectedIdentifier == "child")

        viewModel.leave(from: childLevel)

        #expect(viewModel.level(in: root.nodes).depth == 0)
        #expect(viewModel.selectedIdentifier == "parent")
    }

    @Test("Entering runs the level's onEnter hook")
    func enteringRunsTheOnEnterHook() {
        let counter = CallCounter()
        let node = MenuNode.submenu(id: "parent",
                                    title: "Parent",
                                    onEnter: { counter.increment() },
                                    children: [makeAction(id: "child")])
        let viewModel = MenuPanelViewModel()

        viewModel.enter(node)

        #expect(counter.count == 1)
    }

    @Test("A level whose nodes disappeared falls back to the deepest one that still exists")
    func levelResolutionSurvivesAVanishedNode() {
        let child = makeAction(id: "child")
        let parent = MenuNode.submenu(id: "parent", title: "Parent", children: [child])
        let viewModel = MenuPanelViewModel()

        viewModel.enter(parent)
        #expect(viewModel.level(in: [parent]).depth == 1)

        // The simulator behind this submenu was erased while the panel was open.
        let remaining = [makeAction(id: "before")]
        #expect(viewModel.level(in: remaining).depth == 0)
        #expect(viewModel.level(in: remaining).nodes.identifiers == ["before"])
    }

    @Test("Resetting clears the path, the selection and any pending confirmation")
    func resetClearsEverything() {
        let destructive = makeAction(id: "erase", isDestructive: true)
        let parent = MenuNode.submenu(id: "parent", title: "Parent", children: [destructive])
        let viewModel = MenuPanelViewModel()

        viewModel.enter(parent)
        viewModel.select(destructive)
        viewModel.activateFromKeyboard(destructive)

        viewModel.reset()

        #expect(viewModel.pathIdentifiers.isEmpty)
        #expect(viewModel.selectedIdentifier == nil)
        #expect(viewModel.pendingDestructiveIdentifier == nil)
    }

    // MARK: - Activation

    @Test("Return activates a row's primary action")
    func returnRunsThePrimaryAction() {
        let counter = CallCounter()
        let node = makeAction(id: "action", titles: ["Documents Folder"], counter: counter)
        let viewModel = MenuPanelViewModel()

        #expect(viewModel.activateFromKeyboard(node) == .performed)
        #expect(counter.titles == ["Documents Folder"])
    }

    @Test("Return on a submenu drills in rather than activating")
    func returnOnASubmenuDrillsIn() {
        let counter = CallCounter()
        let node = MenuNode.submenu(id: "app",
                                    title: "App",
                                    actions: makeActions(["Documents Folder", "App Package"], counter: counter),
                                    children: [makeAction(id: "child")])
        let viewModel = MenuPanelViewModel()

        #expect(viewModel.activateFromKeyboard(node) == .entered)
        #expect(counter.titles.isEmpty)
        #expect(viewModel.pathIdentifiers == ["app"])
    }

    @Test("Command-Return and Option-Return reach the first and second secondary actions")
    func modifiersReachSecondaryActions() {
        let counter = CallCounter()
        let titles = ["Documents Folder", "App Package", "User Defaults"]
        let node = MenuNode.submenu(id: "app",
                                    title: "App",
                                    actions: makeActions(titles, counter: counter),
                                    children: [])
        let viewModel = MenuPanelViewModel()

        #expect(viewModel.activateFromKeyboard(node, kind: .secondary(index: 0)) == .performed)
        #expect(viewModel.activateFromKeyboard(node, kind: .secondary(index: 1)) == .performed)

        #expect(counter.titles == ["App Package", "User Defaults"])
    }

    @Test("A missing secondary action does nothing rather than falling back to the primary one")
    func missingSecondaryActionIsIgnored() {
        let counter = CallCounter()
        let node = MenuNode.submenu(id: "app",
                                    title: "App",
                                    actions: makeActions(["Documents Folder", "App Package"], counter: counter),
                                    children: [])
        let viewModel = MenuPanelViewModel()

        #expect(viewModel.activateFromKeyboard(node, kind: .secondary(index: 1)) == .none)
        #expect(counter.titles.isEmpty)
    }

    @Test("A disabled row does nothing")
    func disabledRowsDoNothing() {
        let counter = CallCounter()
        let node = makeAction(id: "action", isEnabled: false, counter: counter)
        let viewModel = MenuPanelViewModel()

        #expect(viewModel.activateFromKeyboard(node) == .none)
        #expect(viewModel.activateFromMouse(node) == .none)
        #expect(counter.titles.isEmpty)
    }

    // MARK: - Destructive guard

    @Test("A destructive row needs a second Return before it runs")
    func destructiveRowsNeedConfirmation() {
        let counter = CallCounter()
        let node = makeAction(id: "erase", isDestructive: true, titles: ["Erase Simulator"], counter: counter)
        let viewModel = MenuPanelViewModel()

        #expect(viewModel.activateFromKeyboard(node) == .awaitingConfirmation)
        #expect(counter.titles.isEmpty)
        #expect(viewModel.isAwaitingConfirmation(node))

        #expect(viewModel.activateFromKeyboard(node) == .performed)
        #expect(counter.titles == ["Erase Simulator"])
        #expect(!viewModel.isAwaitingConfirmation(node))
    }

    @Test("Moving the selection away cancels a pending destructive confirmation")
    func movingAwayCancelsTheConfirmation() {
        let counter = CallCounter()
        let destructive = makeAction(id: "erase", isDestructive: true, counter: counter)
        let level = makeLevel([makeAction(id: "safe"), destructive])
        let viewModel = MenuPanelViewModel()

        viewModel.select(destructive)
        viewModel.activateFromKeyboard(destructive)
        #expect(viewModel.isAwaitingConfirmation(destructive))

        viewModel.moveSelection(.up, in: level)

        #expect(!viewModel.isAwaitingConfirmation(destructive))
        #expect(counter.titles.isEmpty)
    }

    @Test("Hovering another row, and any other key, cancel a pending destructive confirmation")
    func hoverAndOtherKeysCancelTheConfirmation() {
        let destructive = makeAction(id: "erase", isDestructive: true)
        let other = makeAction(id: "safe")
        let viewModel = MenuPanelViewModel()

        viewModel.select(destructive)
        viewModel.activateFromKeyboard(destructive)
        viewModel.select(other)
        #expect(!viewModel.isAwaitingConfirmation(destructive))

        viewModel.select(destructive)
        viewModel.activateFromKeyboard(destructive)
        viewModel.cancelPendingConfirmation()
        #expect(!viewModel.isAwaitingConfirmation(destructive))
    }

    @Test("Confirming one destructive row does not arm another")
    func confirmationIsPerRow() {
        let counter = CallCounter()
        let first = makeAction(id: "erase-one", isDestructive: true, titles: ["One"], counter: counter)
        let second = makeAction(id: "erase-two", isDestructive: true, titles: ["Two"], counter: counter)
        let viewModel = MenuPanelViewModel()

        viewModel.activateFromKeyboard(first)
        #expect(viewModel.activateFromKeyboard(second) == .awaitingConfirmation)
        #expect(counter.titles.isEmpty)
    }

    @Test("A click runs a destructive row immediately, exactly as the menu always did")
    func mouseActivationIsNotGuarded() {
        let counter = CallCounter()
        let node = makeAction(id: "erase", isDestructive: true, titles: ["Erase Simulator"], counter: counter)
        let viewModel = MenuPanelViewModel()

        #expect(viewModel.activateFromMouse(node) == .performed)
        #expect(counter.titles == ["Erase Simulator"])
    }

    @Test("No destructive row is selected when a level is first shown")
    func destructiveRowsAreNeverSelectedOnArrival() {
        let destructive = makeAction(id: "erase", isDestructive: true)
        let parent = MenuNode.submenu(id: "parent", title: "Parent", children: [destructive])
        let viewModel = MenuPanelViewModel()

        #expect(viewModel.selectedIdentifier == nil)

        viewModel.enter(parent)

        #expect(viewModel.selectedIdentifier == nil)
    }

    // MARK: - Hover

    @Test("Hover and keyboard selection are one highlight, and hovering out clears only its own row")
    func hoverDrivesTheSameSelection() {
        let first = makeAction(id: "first")
        let second = makeAction(id: "second")
        let viewModel = MenuPanelViewModel()

        viewModel.select(first)
        #expect(viewModel.isSelected(first))
        #expect(!viewModel.isSelected(second))

        viewModel.clearSelection(ifSelected: second)
        #expect(viewModel.isSelected(first))

        viewModel.clearSelection(ifSelected: first)
        #expect(viewModel.selectedIdentifier == nil)
    }

    @Test("A non-selectable row cannot be selected by hovering it")
    func hoveringANonSelectableRowDoesNothing() {
        let viewModel = MenuPanelViewModel()

        viewModel.select(.sectionHeader(id: "header", title: "Recent Apps"))

        #expect(viewModel.selectedIdentifier == nil)
    }

    @Test("The selected node is only returned while it is still in the level")
    func selectedNodeFollowsTheLevel() {
        let node = makeAction(id: "action")
        let viewModel = MenuPanelViewModel()

        viewModel.select(node)

        #expect(viewModel.selectedNode(in: makeLevel([node]))?.id == "action")
        #expect(viewModel.selectedNode(in: makeLevel([makeAction(id: "other")])) == nil)
    }
}

// MARK: - Helpers

/// Records which actions ran, so a test can assert on the action rather than on a side effect.
@MainActor
private final class CallCounter {
    private(set) var titles: [String] = []

    var count: Int {
        titles.count
    }

    func record(_ title: String) {
        titles.append(title)
    }

    func increment() {
        record("onEnter")
    }
}

private extension MenuPanelViewModelTests {
    func makeLevel(_ nodes: [MenuNode]) -> MenuPanelLevel {
        MenuPanelLevel(title: nil, nodes: nodes, depth: 0)
    }

    func mixedNodes() -> [MenuNode] {
        [
            .sectionHeader(id: "header", title: "Recent Apps"),
            makeAction(id: "first"),
            .divider(id: "divider"),
            .informational(id: "info", title: "No apps installed"),
            makeAction(id: "second"),
            .divider(id: "divider-2"),
            makeAction(id: "third")
        ]
    }

    func makeAction(
        id: String,
        isEnabled: Bool = true,
        isDestructive: Bool = false,
        titles: [String] = ["Action"],
        counter: CallCounter? = nil
    ) -> MenuNode {
        .action(id: id,
                title: titles[0],
                isEnabled: isEnabled,
                isDestructive: isDestructive,
                actions: makeActions(titles, counter: counter))
    }

    func makeActions(_ titles: [String], counter: CallCounter?) -> [MenuActionItem] {
        titles.map { title in
            MenuActionItem(title: title) {
                counter?.record(title)
            }
        }
    }
}
