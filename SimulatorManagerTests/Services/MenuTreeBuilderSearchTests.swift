//
//  MenuTreeBuilderSearchTests.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 04.09.26.
//

import Foundation
import Testing
@testable import SimulatorManager

/// Search hits become `MenuNode`s so the panel renders and activates them with the machinery it
/// already has. These cases pin down that mapping, and the panel behaviour that depends on it.
@Suite("Search results in the menu tree")
@MainActor
struct MenuTreeBuilderSearchTests {
    @Test("An app hit is a flat row carrying its device and its folder actions")
    func appHitCarriesItsFolderActions() throws {
        let fixture = MenuTreeFixture()
        defer { fixture.tearDown() }

        let device = TestDataHelpers.createMockDevice(udid: "device-1", name: "iPhone 16", osVersion: "18.2")
        // Real container URLs, because a shortcut whose URL cannot be resolved is not offered.
        let root = URL(fileURLWithPath: "/tmp/weather-container")
        let app = TestDataHelpers.createMockApp(bundleIdentifier: "com.test.weather",
                                                displayName: "Weather Station",
                                                appDocumentsFolderURL: root.appendingPathComponent("Data"),
                                                appPackageURL: root.appendingPathComponent("Weather.app"),
                                                userDefaultsDomains: ["com.test.weather"])
        let result = MenuSearchResult(id: "app-com.test.weather-device-1",
                                      kind: .app(app: app, device: device),
                                      title: app.displayName,
                                      subtitle: "iPhone 16 18.2",
                                      iconName: app.iconName)

        let nodes = fixture.makeBuilder().searchResultNodes(for: [result])
        let node = try #require(nodes.first)

        #expect(nodes.count == 1)
        #expect(node.id == "search.app-com.test.weather-device-1")
        #expect(node.title == "Weather Station")
        // The subtitle is not decoration: the same app is typically installed on many simulators.
        #expect(node.subtitle == "iPhone 16 18.2")
        #expect(!node.isSubmenu)
        #expect(node.primaryAction?.title == "Documents Folder")
        #expect(node.secondaryActions.map(\.title) == ["App Package", "User Defaults"])
    }

    @Test("A device hit opens its simulator folder and offers nothing to drill into")
    func deviceHitOpensItsSimulatorFolder() throws {
        let fixture = MenuTreeFixture()
        defer { fixture.tearDown() }

        let device = TestDataHelpers.createMockDevice(udid: "device-1", name: "iPhone 16", osVersion: "18.2")
        let result = MenuSearchResult(id: "device-device-1",
                                      kind: .device(device),
                                      title: device.name,
                                      subtitle: device.osVersion,
                                      iconName: device.simulatorPlatform.iconName)

        let node = try #require(fixture.makeBuilder().searchResultNodes(for: [result]).first)

        #expect(node.title == "iPhone 16")
        #expect(node.subtitle == "18.2")
        #expect(!node.isSubmenu)
        #expect(node.primaryAction?.title == "Simulator Folder")
        #expect(node.secondaryActions.isEmpty)
    }

    @Test("Every result is selectable, so nothing in a filtered list is skipped by the arrow keys")
    func everyResultIsSelectable() {
        let fixture = MenuTreeFixture()
        defer { fixture.tearDown() }

        let device = TestDataHelpers.createMockDevice(udid: "device-1", name: "iPhone 16")
        let results = (0 ..< 3).map { index in
            MenuSearchResult(id: "app-com.test.\(index)-device-1",
                             kind: .app(app: TestDataHelpers.createMockApp(bundleIdentifier: "com.test.\(index)",
                                                                           displayName: "App \(index)"),
                                        device: device),
                             title: "App \(index)",
                             subtitle: "iPhone 16 17.0",
                             iconName: "iphone.gen3")
        }

        let nodes = fixture.makeBuilder().searchResultNodes(for: results)
        // Computed outside the macro: `#expect` decomposes the call and treats a key-path argument
        // to `allSatisfy` as throwing.
        let selectableCount = nodes.filter(\.isSelectable).count

        #expect(nodes.count == 3)
        #expect(selectableCount == 3)
    }

    @Test("The top hit is selected as soon as results appear, and again whenever the query changes")
    func selectionFollowsTheResults() {
        let panelViewModel = MenuPanelViewModel()
        let firstResults = makeLevel(["search.one", "search.two"])

        panelViewModel.applyQueryChange(isSearching: true, resultLevel: firstResults)
        #expect(panelViewModel.selectedIdentifier == "search.one")

        // The user typed another character and the list reordered under them.
        let reorderedResults = makeLevel(["search.three", "search.one"])
        panelViewModel.applyQueryChange(isSearching: true, resultLevel: reorderedResults)

        #expect(panelViewModel.selectedIdentifier == "search.three")
    }

    @Test("Clearing the query returns to the browsable menu at its top level")
    func clearingTheQueryReturnsToBrowsing() {
        let panelViewModel = MenuPanelViewModel()
        let submenu = MenuNode.submenu(id: "parent", title: "Parent", children: [])

        panelViewModel.enter(submenu)
        panelViewModel.applyQueryChange(isSearching: true, resultLevel: makeLevel(["search.one"]))
        #expect(panelViewModel.selectedIdentifier == "search.one")

        panelViewModel.applyQueryChange(isSearching: false, resultLevel: makeLevel([]))

        #expect(panelViewModel.pathIdentifiers.isEmpty)
        #expect(panelViewModel.selectedIdentifier == nil)
    }

    @Test("A query that matched nothing leaves the selection empty rather than stale")
    func noMatchesClearsTheSelection() {
        let panelViewModel = MenuPanelViewModel()

        panelViewModel.applyQueryChange(isSearching: true, resultLevel: makeLevel(["search.one"]))
        panelViewModel.applyQueryChange(isSearching: true, resultLevel: makeLevel([]))

        #expect(panelViewModel.selectedIdentifier == nil)
    }

    @Test("Return opens the selected hit, and the modifiers reach its other folders")
    func activatingAHitOpensTheRightFolder() {
        let fixture = MenuTreeFixture()
        defer { fixture.tearDown() }

        let opened = OpenedFolders()
        let node = MenuNode.action(id: "search.app",
                                   title: "Weather Station",
                                   subtitle: "iPhone 16 18.2",
                                   actions: ["Documents Folder", "App Package", "User Defaults"].map { title in
                                       MenuActionItem(title: title) { opened.record(title) }
                                   })
        let panelViewModel = MenuPanelViewModel()

        panelViewModel.select(node)

        #expect(panelViewModel.activateFromKeyboard(node) == .performed)
        #expect(panelViewModel.activateFromKeyboard(node, kind: .secondary(index: 0)) == .performed)
        #expect(panelViewModel.activateFromKeyboard(node, kind: .secondary(index: 1)) == .performed)

        #expect(opened.titles == ["Documents Folder", "App Package", "User Defaults"])
    }
}

// MARK: - Helpers

@MainActor
private final class OpenedFolders {
    private(set) var titles: [String] = []

    func record(_ title: String) {
        titles.append(title)
    }
}

private extension MenuTreeBuilderSearchTests {
    func makeLevel(_ identifiers: [String]) -> MenuPanelLevel {
        let nodes = identifiers.map { identifier in
            MenuNode.action(id: identifier,
                            title: identifier,
                            actions: [MenuActionItem(title: identifier) {}])
        }

        return MenuPanelLevel(title: nil, nodes: nodes, depth: 0)
    }
}
