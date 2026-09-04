//
//  MenuTreeBuilder.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 04.09.26.
//

import Foundation

/// Describes the menu bar menu as a ``MenuNode`` tree.
///
/// A pure function of its inputs: given the same view-model state it produces the same tree, it
/// touches no files, and it subscribes to nothing. Whoever renders the tree is responsible for
/// rebuilding it when observed state changes.
@MainActor
struct MenuTreeBuilder {
    let simulatorManagerViewModel: SimulatorManagerViewModel
    let settingsViewModel: SettingsViewModel
    let cleanupViewModel: CleanupSimulatorsViewModel
    let resetViewModel: ResetSimulatorsViewModel
    let settings: Settings
    let githubService: GithubService
    /// Defaults to the running bundle's version, and stays injectable so the version section can
    /// be exercised without depending on whichever bundle the tests happen to run in.
    var appVersion: String? = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    let openPreferences: @MainActor () -> Void
    let quit: @MainActor () -> Void

    func makeNodes() -> [MenuNode] {
        var nodes = recentAppsNodes()

        nodes.append(.divider(id: "divider.afterRecentApps"))
        nodes.append(contentsOf: deviceTypeNodes())
        nodes.append(.divider(id: "divider.afterDeviceTypes"))
        nodes.append(contentsOf: settingsNodes())
        nodes.append(preferencesNode())
        nodes.append(.divider(id: "divider.afterSettings"))
        nodes.append(cleanupNode())
        nodes.append(.divider(id: "divider.afterCleanup"))
        nodes.append(resetNode())
        nodes.append(.divider(id: "divider.afterReset"))
        nodes.append(contentsOf: gitHubNodes())
        nodes.append(.divider(id: "divider.afterGitHub"))
        nodes.append(quitNode())

        return nodes
    }
}

// MARK: - Recent apps

extension MenuTreeBuilder {
    func recentAppsNodes() -> [MenuNode] {
        guard settings.showRecentApps else {
            return []
        }

        let recentApps = simulatorManagerViewModel.recentInstalledApps

        guard !recentApps.isEmpty else {
            return [.informational(id: "recentApps.empty", title: "No Recent Apps")]
        }

        let header = MenuNode.sectionHeader(id: "recentApps.header", title: "Recent Apps")

        return [header] + recentApps.map { recentAppNode(for: $0) }
    }

    private func recentAppNode(for appChange: AppChange) -> MenuNode {
        let identifier = "recentApp.\(appChange.app.bundleIdentifier).\(appChange.device.udid)"
        let actions = folderActions(for: appChange.app, folderOpening: simulatorManagerViewModel)

        return .submenu(id: identifier,
                        title: appChange.app.displayName,
                        subtitle: "\(appChange.device.name) \(appChange.device.osVersion)",
                        actions: actions,
                        children: actionNodes(identifierPrefix: identifier, actions: actions))
    }
}

// MARK: - Devices

extension MenuTreeBuilder {
    func deviceTypeNodes() -> [MenuNode] {
        simulatorManagerViewModel.deviceTypes
            .filter { settings.visiblePlatforms.contains($0.simulatorPlatform) }
            .map { deviceType in
                let devices = simulatorManagerViewModel.devices.filter { $0.name == deviceType.name }

                return .submenu(id: "deviceType.\(deviceType.id)",
                                title: deviceType.name,
                                children: devices.flatMap { deviceNodes(for: $0) })
            }
    }

    private func deviceNodes(for device: Device) -> [MenuNode] {
        let viewModel = simulatorManagerViewModel.makeDeviceViewModel(for: device)
        let prefix = "device.\(device.udid)"
        var nodes: [MenuNode] = [.informational(id: "\(prefix).state", title: viewModel.stateDescription)]

        if let actionErrorMessage = viewModel.actionErrorMessage {
            nodes.append(.informational(id: "\(prefix).error", title: actionErrorMessage))
        }

        if viewModel.hasAppsInstalled {
            nodes.append(.submenu(id: "\(prefix).contents",
                                  title: viewModel.osVersion,
                                  children: deviceContentNodes(for: viewModel, prefix: prefix)))
        } else {
            nodes.append(.informational(id: "\(prefix).osVersion", title: viewModel.osVersion))
            nodes.append(.informational(id: "\(prefix).noApps", title: "No apps installed"))
        }

        nodes.append(contentsOf: deviceFolderNodes(for: viewModel, prefix: prefix))

        if viewModel.isPerformingAction {
            nodes.append(.informational(id: "\(prefix).actionProgress", title: viewModel.currentActionTitle))
        } else {
            nodes.append(.action(id: "\(prefix).erase",
                                 title: "Erase Simulator",
                                 isDestructive: true,
                                 actions: [MenuActionItem(title: "Erase Simulator") { viewModel.eraseDevice() }]))
        }

        nodes.append(.divider(id: "\(prefix).divider"))

        return nodes
    }

    private func deviceFolderNodes(for viewModel: DeviceViewModel, prefix: String) -> [MenuNode] {
        let device = viewModel.device
        var nodes: [MenuNode] = [
            .action(id: "\(prefix).simulatorFolder",
                    title: "Simulator Folder",
                    actions: [MenuActionItem(title: "Simulator Folder") { viewModel.didSelectSimulatorFolder(for: device) }])
        ]

        if viewModel.hasAppsFolder {
            nodes.append(.action(id: "\(prefix).appFolder",
                                 title: "App Folder",
                                 actions: [MenuActionItem(title: "App Folder") { viewModel.didSelectAppsFolder(for: device) }]))
        }

        if viewModel.hasAppPackagesFolder {
            nodes.append(.action(id: "\(prefix).appPackageFolder",
                                 title: "App Package Folder",
                                 actions: [MenuActionItem(title: "App Package Folder") { viewModel.didSelectAppPackagesFolder(for: device) }]))
        }

        return nodes
    }

    /// The contents of a device's OS-version submenu: apps, then app groups, fenced by the same
    /// dividers the menu draws today.
    private func deviceContentNodes(for viewModel: DeviceViewModel, prefix: String) -> [MenuNode] {
        [.divider(id: "\(prefix).contents.dividerTop")]
            + appNodes(for: viewModel, prefix: prefix)
            + [.divider(id: "\(prefix).contents.dividerMiddle")]
            + appGroupNodes(for: viewModel, prefix: prefix)
            + [.divider(id: "\(prefix).contents.dividerBottom")]
    }

    private func appNodes(for viewModel: DeviceViewModel, prefix: String) -> [MenuNode] {
        var nodes: [MenuNode] = []

        // Transcribed from `AppsView` as written: it draws the "Apps" header only when the device
        // has *no* apps installed. That cannot happen, because the header is reached only from
        // inside the apps submenu, which is itself conditional on apps existing — so the header
        // never appears today. Kept as-is so the tree matches the menu rather than changing it.
        if !viewModel.device.hasAppsInstalled {
            nodes.append(.sectionHeader(id: "\(prefix).apps.header", title: "Apps"))
        }

        nodes.append(contentsOf: viewModel.apps.map { app in
            let identifier = "\(prefix).app.\(app.bundleIdentifier)"
            let actions = folderActions(for: app, folderOpening: viewModel)

            return .submenu(id: identifier,
                            title: app.displayName,
                            actions: actions,
                            children: actionNodes(identifierPrefix: identifier, actions: actions))
        })

        return nodes
    }

    private func appGroupNodes(for viewModel: DeviceViewModel, prefix: String) -> [MenuNode] {
        var nodes: [MenuNode] = []

        if !viewModel.appGroups.isEmpty {
            nodes.append(.sectionHeader(id: "\(prefix).appGroups.header", title: "AppGroups"))
        }

        nodes.append(contentsOf: viewModel.device.appGroups.map { appGroup in
            let identifier = "\(prefix).appGroup.\(appGroup.identifier)"
            var actions = [MenuActionItem(title: "Group Folder") { viewModel.didSelect(appGroup: appGroup) }]

            if appGroup.hasUserDefaults {
                actions.append(MenuActionItem(title: "Group UserDefaults") {
                    viewModel.didSelectUserDefaultsFolder(for: appGroup)
                })
            }

            return .submenu(id: identifier,
                            title: "Group \(appGroup.name)",
                            actions: actions,
                            children: actionNodes(identifierPrefix: identifier, actions: actions))
        })

        return nodes
    }
}

// MARK: - Settings

extension MenuTreeBuilder {
    func settingsNodes() -> [MenuNode] {
        var nodes: [MenuNode] = [
            toggleNode(identifier: "settings.recentApps", title: settingsViewModel.showRecentAppsText) {
                settingsViewModel.toggleRecentAppsVisibility()
            },
            .divider(id: "settings.divider")
        ]

        if settingsViewModel.hasAppleTVDevices {
            nodes.append(toggleNode(identifier: "settings.tvOS", title: settingsViewModel.showAppleTVText) {
                settingsViewModel.toggleTVOSVisibility()
            })
        }

        if settingsViewModel.hasVisionProDevices {
            nodes.append(toggleNode(identifier: "settings.visionOS", title: settingsViewModel.showVisionText) {
                settingsViewModel.toggleVisionOSVisibility()
            })
        }

        if settingsViewModel.hasWatchDevices {
            nodes.append(toggleNode(identifier: "settings.watchOS", title: settingsViewModel.showWatchText) {
                settingsViewModel.toggleWatchOSVisibility()
            })
        }

        if settingsViewModel.hasIPadDevices {
            nodes.append(toggleNode(identifier: "settings.iPadOS", title: settingsViewModel.showIPadText) {
                settingsViewModel.toggleIPadOSVisibility()
            })
        }

        if settingsViewModel.hasIPhoneDevices {
            nodes.append(toggleNode(identifier: "settings.iOS", title: settingsViewModel.showIPhoneText) {
                settingsViewModel.toggleIOSVisibility()
            })
        }

        return nodes
    }

    func preferencesNode() -> MenuNode {
        .action(id: "settings.open",
                title: "Settings…",
                actions: [MenuActionItem(title: "Settings…", perform: openPreferences)])
    }

    private func toggleNode(
        identifier: String,
        title: String,
        perform: @escaping @MainActor () -> Void
    ) -> MenuNode {
        .action(id: identifier, title: title, actions: [MenuActionItem(title: title, perform: perform)])
    }
}

// MARK: - Reset, GitHub and Quit

extension MenuTreeBuilder {
    func resetNode() -> MenuNode {
        let confirmTitle = "Confirm Reset All Simulators"
        let confirmAction = MenuActionItem(title: confirmTitle) { resetViewModel.resetAllSimulators() }
        let confirmNode = MenuNode.action(id: "reset.confirm",
                                          title: confirmTitle,
                                          isDestructive: true,
                                          actions: [confirmAction])
        let children: [MenuNode]

        if resetViewModel.isResettingSimulators {
            children = [.informational(id: "reset.progress", title: "Resetting...")]
        } else {
            children = [confirmNode]
        }

        return .submenu(id: "reset",
                        title: resetViewModel.resetButtonText,
                        iconName: resetViewModel.resetButtonIcon,
                        isEnabled: !resetViewModel.isResettingSimulators,
                        children: children)
    }

    func gitHubNodes() -> [MenuNode] {
        var nodes: [MenuNode] = [
            .action(id: "github.project",
                    title: "GitHub Project",
                    actions: [MenuActionItem(title: "GitHub Project") { githubService.openGithubProject() }])
        ]

        guard let appVersion else {
            return nodes
        }

        nodes.append(.divider(id: "github.divider"))

        if githubService.isUpdateAvailable {
            nodes.append(.action(id: "github.update",
                                 title: "Update Available",
                                 subtitle: "Version \(appVersion)",
                                 iconName: "info.circle.fill",
                                 actions: [MenuActionItem(title: "Update Available") { githubService.openLatestRelease() }]))
        } else {
            nodes.append(.informational(id: "github.version", title: "Version \(appVersion)"))
        }

        return nodes
    }

    func quitNode() -> MenuNode {
        .action(id: "quit", title: "Quit", actions: [MenuActionItem(title: "Quit", perform: quit)])
    }
}

// MARK: - Shared helpers

extension MenuTreeBuilder {
    /// The folder actions an app offers, primary first. Same order the app's submenu uses today,
    /// so `⌘↩` reaching "App Package" matches what a drill-down would show.
    func folderActions(for app: any SimulatorApp, folderOpening: any FolderOpening) -> [MenuActionItem] {
        var actions = [
            MenuActionItem(title: "Documents Folder") { folderOpening.didSelectAppDocumentFolder(for: app) },
            MenuActionItem(title: "App Package") { folderOpening.didSelectAppPackageFolder(for: app) }
        ]

        if app.hasUserDefaults {
            actions.append(MenuActionItem(title: "User Defaults") {
                folderOpening.didSelectUserDefaultsFolder(for: app)
            })
        }

        return actions
    }

    /// Renders an action list as the rows of a drill-down level.
    func actionNodes(identifierPrefix: String, actions: [MenuActionItem]) -> [MenuNode] {
        actions.map { action in
            .action(id: "\(identifierPrefix).\(MenuNode.identifierComponent(from: action.title))",
                    title: action.title,
                    actions: [action])
        }
    }
}
