//
//  MenuPanelView.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 04.09.26.
//

import SwiftUI

/// The menu bar panel that replaces the native `NSMenu`.
///
/// A real menu cannot filter its items as you type, and no API makes it do so, which is why the
/// menu becomes a `.menuBarExtraStyle(.window)` panel. Everything `NSMenu` used to supply — rows,
/// drill-down, dismissal — is rebuilt here.
///
/// The tree is rebuilt on every render rather than captured when the panel opens, so state that
/// arrives while it is open (an app installed in a running simulator, a finished cleanup) lands in
/// the panel instead of being frozen out of it.
struct MenuPanelView: View {
    let simulatorManagerViewModel: SimulatorManagerViewModel
    let settingsViewModel: SettingsViewModel
    let cleanupViewModel: CleanupSimulatorsViewModel
    let resetViewModel: ResetSimulatorsViewModel
    @ObservedObject var settings: Settings
    @ObservedObject var githubService: GithubService
    /// Closing the panel is the same status-item operation as opening it, so it goes through the
    /// abstraction that already isolates that from the rest of the app.
    let menuPresenter: any MenuBarMenuPresenting

    @Environment(\.openWindow) private var openWindow
    @State private var viewModel = MenuPanelViewModel()
    @State private var listHeight: CGFloat = MenuPanelStyle.rowMinimumHeight
    @FocusState private var isFocused: Bool

    var body: some View {
        let level = viewModel.level(in: makeNodes())

        VStack(alignment: .leading, spacing: 0) {
            if let title = level.title {
                MenuPanelHeaderView(title: title) {
                    viewModel.leave(from: level)
                }

                Divider()
            }

            rowList(for: level)
        }
        .frame(width: MenuPanelStyle.width)
        .background(shortcuts)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear {
            isFocused = true
        }
        .onDisappear {
            // Reopening starts at the top level, the way reopening a menu does.
            viewModel.reset()
        }
        .onExitCommand {
            dismiss()
        }
        .task {
            githubService.startPeriodicUpdateCheck()
        }
    }
}

private extension MenuPanelView {
    func makeNodes() -> [MenuNode] {
        MenuTreeBuilder(simulatorManagerViewModel: simulatorManagerViewModel,
                        settingsViewModel: settingsViewModel,
                        cleanupViewModel: cleanupViewModel,
                        resetViewModel: resetViewModel,
                        settings: settings,
                        githubService: githubService,
                        openPreferences: openPreferences,
                        quit: quit)
            .makeNodes()
    }

    func rowList(for level: MenuPanelLevel) -> some View {
        ScrollView {
            // A plain stack rather than a lazy one: a single menu level is small, and rendering it
            // eagerly keeps scroll-into-view and offscreen rendering working, both of which a
            // `LazyVStack` breaks by not materialising rows that are not on screen.
            VStack(alignment: .leading, spacing: 0) {
                ForEach(level.nodes) { node in
                    MenuPanelRowView(node: node) {
                        activate(node)
                    }
                }
            }
            .padding(.vertical, MenuPanelStyle.listVerticalPadding)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                listHeight = height
            }
        }
        // A `ScrollView` has no intrinsic height, and the window a `MenuBarExtra` puts it in
        // imposes none — left to itself the panel collapses to a ten-point sliver. So the rows are
        // measured and the panel is sized to them, capped so that a machine with dozens of
        // simulators gets a scrolling panel instead of one taller than the screen.
        .frame(height: min(max(listHeight, MenuPanelStyle.rowMinimumHeight), MenuPanelStyle.maximumListHeight))
        .scrollBounceBehavior(.basedOnSize)
    }

    func activate(_ node: MenuNode) {
        guard node.isEnabled else {
            return
        }

        if node.isSubmenu {
            viewModel.enter(node)

            return
        }

        guard let action = node.primaryAction else {
            return
        }

        // Picking a menu item closes the menu; picking a row closes the panel.
        action.perform()
        dismiss()
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    func dismiss() {
        menuPresenter.closeMenu()
    }

    /// The app is an agent, so it is not brought to the front on its own and the settings window
    /// would otherwise open behind whatever the user was working in.
    func openPreferences() {
        dismiss()
        openWindow(id: PreferencesWindow.identifier)
        NSApp.activate()
    }

    /// ⌘Q and ⌘, came free from `Button.keyboardShortcut` inside an `NSMenu`. The rows are plain
    /// views now, so the shortcuts are attached to invisible buttons instead of being lost.
    var shortcuts: some View {
        ZStack {
            Button("Quit") {
                quit()
            }
            .keyboardShortcut("q", modifiers: .command)

            Button("Settings") {
                openPreferences()
            }
            .keyboardShortcut(",", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}

/// Header of a drilled-into level: the submenu's title, and the way back out.
struct MenuPanelHeaderView: View {
    let title: String
    let goBack: () -> Void

    var body: some View {
        Button(action: goBack) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))

                Text(title)
                    .font(MenuPanelStyle.titleFont.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, MenuPanelStyle.rowHorizontalPadding + MenuPanelStyle.horizontalInset)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to \(title)")
    }
}
