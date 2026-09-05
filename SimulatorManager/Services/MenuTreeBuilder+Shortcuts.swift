//
//  MenuTreeBuilder+Shortcuts.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 05.09.26.
//

import Foundation

/// The container shortcuts a row offers: open the folder, copy its path, and — for preferences —
/// copy the content itself.
///
/// `AppContainerShortcut` and `AppGroupShortcut` already describe which shortcuts resolve for a
/// given container, so the tree is built from those rather than from a second hand-written list
/// that could drift from the menu.
extension MenuTreeBuilder {
    /// The actions reachable with a modifier, primary first.
    ///
    /// Only the open-the-folder shortcuts: `⌘↩` and `⌥↩` mean "open a different folder", and
    /// quietly copying a path instead would be a surprise. Copying stays a drill-down.
    func openActions(
        for app: any SimulatorApp,
        handler: any ContainerShortcutHandling
    ) -> [MenuActionItem] {
        AppContainerShortcut.available(for: app).map { shortcut in
            MenuActionItem(title: shortcut.title) {
                handler.didSelectFolder(shortcut, for: app)
            }
        }
    }

    /// Everything an app's submenu shows, in the order the menu draws it.
    func shortcutNodes(
        for app: any SimulatorApp,
        handler: any ContainerShortcutHandling,
        identifierPrefix prefix: String
    ) -> [MenuNode] {
        let shortcuts = AppContainerShortcut.available(for: app)
        let openNodes = shortcuts.map { shortcut in
            MenuNode.action(id: "\(prefix).open.\(shortcut.rawValue)", title: shortcut.title) {
                handler.didSelectFolder(shortcut, for: app)
            }
        }
        let copyPathChildren = shortcuts.map { shortcut in
            MenuNode.action(id: "\(prefix).copyPath.\(shortcut.rawValue)", title: shortcut.title) {
                handler.didSelectCopyPath(of: shortcut, for: app)
            }
        }

        return openNodes
            + [.divider(id: "\(prefix).divider"), copyPathNode(prefix: prefix, children: copyPathChildren)]
            + userDefaultsNodes(prefix: prefix, domains: app.exportableUserDefaultsDomains) { domain in
                handler.didSelectCopyUserDefaultsJSON(for: app, domain: domain)
            }
    }

    /// The same for an app group's shared container.
    func shortcutNodes(
        for appGroup: AppGroup,
        handler: any ContainerShortcutHandling,
        identifierPrefix prefix: String
    ) -> [MenuNode] {
        let shortcuts = AppGroupShortcut.available(for: appGroup)
        let openNodes = shortcuts.map { shortcut in
            MenuNode.action(id: "\(prefix).open.\(shortcut.rawValue)", title: shortcut.title) {
                handler.didSelectFolder(shortcut, for: appGroup)
            }
        }
        let copyPathChildren = shortcuts.map { shortcut in
            MenuNode.action(id: "\(prefix).copyPath.\(shortcut.rawValue)", title: shortcut.title) {
                handler.didSelectCopyPath(of: shortcut, for: appGroup)
            }
        }

        return openNodes
            + [.divider(id: "\(prefix).divider"), copyPathNode(prefix: prefix, children: copyPathChildren)]
            + userDefaultsNodes(prefix: prefix, domains: appGroup.exportableUserDefaultsDomains) { domain in
                handler.didSelectCopyUserDefaultsJSON(for: appGroup, domain: domain)
            }
    }

    func openActions(
        for appGroup: AppGroup,
        handler: any ContainerShortcutHandling
    ) -> [MenuActionItem] {
        AppGroupShortcut.available(for: appGroup).map { shortcut in
            MenuActionItem(title: shortcut.title) {
                handler.didSelectFolder(shortcut, for: appGroup)
            }
        }
    }
}

// MARK: - Shared pieces

private extension MenuTreeBuilder {
    func copyPathNode(prefix: String, children: [MenuNode]) -> MenuNode {
        .submenu(id: "\(prefix).copyPath", title: Self.copyPathTitle, children: children)
    }

    /// A container usually holds several defaults domains — its own plus whatever suites its SDKs
    /// created — so each is offered separately. A container with a single domain keeps the flat
    /// item: the common case should not grow a level of nesting for one entry.
    func userDefaultsNodes(
        prefix: String,
        domains: [String],
        copy: @escaping @MainActor (String?) -> Void
    ) -> [MenuNode] {
        guard !domains.isEmpty else {
            return []
        }
        guard domains.count > 1 else {
            return [.action(id: "\(prefix).copyUserDefaults", title: Self.copyUserDefaultsTitle) { copy(nil) }]
        }

        let allDomains = MenuNode.action(id: "\(prefix).copyUserDefaults.all", title: "All Domains") { copy(nil) }
        let perDomain = domains.map { domain in
            MenuNode.action(id: "\(prefix).copyUserDefaults.\(domain)", title: domain) { copy(domain) }
        }

        return [
            .submenu(id: "\(prefix).copyUserDefaults",
                     title: Self.copyUserDefaultsTitle,
                     children: [allDomains, .divider(id: "\(prefix).copyUserDefaults.divider")] + perDomain)
        ]
    }

    static let copyPathTitle = "Copy Path"
    static let copyUserDefaultsTitle = "Copy UserDefaults as JSON"
}
