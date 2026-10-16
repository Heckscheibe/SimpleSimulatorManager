//
//  MenuNodeTidyingTests.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 07.09.26.
//

import Foundation
import Testing
@testable import SimulatorManager

/// The tree is assembled from sections that each append their own divider, so an empty section
/// leaves a rule with nothing on one side of it. `NSMenu` collapsed those itself and nobody had to
/// think about it; a panel draws exactly what the tree says.
@Suite("Menu level tidying")
struct MenuNodeTidyingTests {
    @Test("A rule at the end of a level is dropped")
    func trailingDividersAreDropped() {
        // What a simulator with apps but no app groups produced: the app-groups section contributed
        // nothing but its own separator.
        let nodes: [MenuNode] = [Self.action("app"), .divider(id: "divider")]

        #expect(nodes.tidied().identifiers == ["app"])
    }

    @Test("Two rules in a row become one")
    func consecutiveDividersCollapse() {
        let nodes: [MenuNode] = [
            Self.action("app"),
            .divider(id: "first"),
            .divider(id: "second"),
            Self.action("erase")
        ]

        // Two rules do not read as one separator, they read as an empty row between them.
        #expect(nodes.tidied().identifiers == ["app", "first", "erase"])
    }

    @Test("A rule at the start of a level is dropped")
    func leadingDividersAreDropped() {
        let nodes: [MenuNode] = [.divider(id: "divider"), Self.action("app")]

        #expect(nodes.tidied().identifiers == ["app"])
    }

    @Test("A heading with nothing under it is dropped")
    func emptyHeadingsAreDropped() {
        let nodes: [MenuNode] = [
            .sectionHeader(id: "apps.header", title: "Apps"),
            Self.action("app"),
            .sectionHeader(id: "appGroups.header", title: "AppGroups")
        ]

        // A heading for rows that are not there reads as a section that failed to load.
        #expect(nodes.tidied().identifiers == ["apps.header", "app"])
    }

    @Test("Two headings running together drop the empty one")
    func headingsWithNothingBetweenThemCollapse() {
        let nodes: [MenuNode] = [
            .sectionHeader(id: "apps.header", title: "Apps"),
            .sectionHeader(id: "appGroups.header", title: "AppGroups"),
            Self.action("group")
        ]

        #expect(nodes.tidied().identifiers == ["appGroups.header", "group"])
    }

    @Test("Separators that separate something are left alone")
    func meaningfulSeparatorsSurvive() {
        let nodes: [MenuNode] = [
            Self.action("app"),
            .divider(id: "divider"),
            .sectionHeader(id: "header", title: "AppGroups"),
            Self.action("group")
        ]

        #expect(nodes.tidied().identifiers == nodes.identifiers)
    }

    @Test("A level built for the panel is tidied on the way in")
    func levelsAreTidiedWhenBuilt() {
        // Every level goes through this initializer, which is what makes tidying impossible to
        // forget for a flyout.
        let level = MenuPanelLevel(title: nil,
                                   nodes: [Self.action("app"), .divider(id: "divider")],
                                   depth: 0)

        #expect(level.nodes.identifiers == ["app"])
    }
}

private extension MenuNodeTidyingTests {
    static func action(_ identifier: String) -> MenuNode {
        .action(id: identifier, title: identifier) {}
    }
}
