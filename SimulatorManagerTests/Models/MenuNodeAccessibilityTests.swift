//
//  MenuNodeAccessibilityTests.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 05.09.26.
//

import Foundation
import Testing
@testable import SimulatorManager

/// `NSMenu` was accessible for free; a stack of SwiftUI views is not. These cases pin down what
/// VoiceOver is told about a row.
@Suite("MenuNode accessibility")
struct MenuNodeAccessibilityTests {
    @Test("A plain row announces its title")
    func plainRowAnnouncesItsTitle() {
        let node = MenuNode.action(id: "folder",
                                   title: "Simulator Folder",
                                   actions: [MenuActionItem(title: "Simulator Folder") {}])

        #expect(node.accessibilityLabel == "Simulator Folder")
        #expect(node.accessibilityHint(isAwaitingConfirmation: false).isEmpty)
    }

    @Test("An app hit announces the device it belongs to")
    func appHitAnnouncesItsDevice() {
        let node = MenuNode.action(id: "search.app",
                                   title: "Weather Station",
                                   subtitle: "iPhone 16 Pro 18.2",
                                   actions: [MenuActionItem(title: "Documents Folder") {}])

        // Without the device this is useless: the same app is typically on many simulators.
        #expect(node.accessibilityLabel == "Weather Station, iPhone 16 Pro 18.2")
    }

    @Test("A destructive row says so, and a disabled one says it is dimmed")
    func destructiveAndDisabledRowsAreAnnounced() {
        let destructive = MenuNode.action(id: "erase",
                                          title: "Erase Simulator",
                                          isDestructive: true,
                                          actions: [MenuActionItem(title: "Erase Simulator") {}])
        let disabled = MenuNode.action(id: "refresh",
                                       title: "Refresh Cleanup Scan",
                                       isEnabled: false,
                                       actions: [MenuActionItem(title: "Refresh Cleanup Scan") {}])

        #expect(destructive.accessibilityLabel == "Erase Simulator, destructive")
        #expect(disabled.accessibilityLabel == "Refresh Cleanup Scan, dimmed")
    }

    @Test("A row waiting for confirmation announces that it is waiting")
    func pendingConfirmationIsAnnounced() {
        let node = MenuNode.action(id: "erase",
                                   title: "Erase Simulator",
                                   isDestructive: true,
                                   actions: [MenuActionItem(title: "Erase Simulator") {}])

        #expect(node.accessibilityHint(isAwaitingConfirmation: true) == "Press Return again to confirm")
    }

    @Test("A submenu says that it opens one")
    func submenusSayTheyOpen() {
        let node = MenuNode.submenu(id: "deviceType", title: "iPhone 16 Pro", children: [])

        #expect(node.accessibilityHint(isAwaitingConfirmation: false) == "Opens a submenu")
    }

    @Test("Section headers are distinguishable from other non-interactive rows")
    func sectionHeadersAreDistinguishable() {
        let header = MenuNode.sectionHeader(id: "recentApps.header", title: "Recent Apps")
        let informational = MenuNode.informational(id: "recentApps.empty", title: "No Recent Apps")

        #expect(header.kind.isSectionHeader)
        #expect(!informational.kind.isSectionHeader)
        // Neither can be landed on by the arrow keys.
        #expect(!header.isSelectable)
        #expect(!informational.isSelectable)
    }
}
