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
/// drill-down, arrow navigation, dismissal — is rebuilt here.
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
    @Bindable var searchViewModel: MenuSearchViewModel

    @Environment(\.openWindow) private var openWindow
    @State private var viewModel = MenuPanelViewModel()
    @State private var listHeight: CGFloat = MenuPanelStyle.rowMinimumHeight

    var body: some View {
        let level = currentLevel()

        VStack(alignment: .leading, spacing: 0) {
            MenuPanelSearchField(query: $searchViewModel.query,
                                 placeholder: "Search simulators and apps") { command in
                perform(command, in: currentLevel())
            }
            .padding(.horizontal, MenuPanelStyle.horizontalInset + 3)
            .padding(.vertical, MenuPanelStyle.listVerticalPadding + 2)

            Divider()

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
        .onChange(of: searchViewModel.query) { _, _ in
            queryChanged()
        }
        .onDisappear {
            // Reopening starts at the top level, with nothing selected and an empty query — the way
            // reopening a menu does.
            viewModel.reset()
            searchViewModel.clear()
        }
        .task {
            githubService.startPeriodicUpdateCheck()
        }
    }
}

// MARK: - Rows

private extension MenuPanelView {
    /// The rows on screen: the ranked hits while there is a query, and the browsable menu when
    /// there is not. Both go through the same drill-down resolution, so one renderer, one selection
    /// model and one activation path serve both modes.
    func currentLevel() -> MenuPanelLevel {
        viewModel.level(in: searchViewModel.hasQuery ? searchResultNodes() : makeNodes())
    }

    func searchResultNodes() -> [MenuNode] {
        makeBuilder().searchResultNodes(for: searchViewModel.results)
    }

    func makeNodes() -> [MenuNode] {
        makeBuilder().makeNodes()
    }

    func makeBuilder() -> MenuTreeBuilder {
        MenuTreeBuilder(simulatorManagerViewModel: simulatorManagerViewModel,
                        settingsViewModel: settingsViewModel,
                        cleanupViewModel: cleanupViewModel,
                        resetViewModel: resetViewModel,
                        settings: settings,
                        githubService: githubService,
                        openPreferences: openPreferences,
                        quit: quit)
    }

    func rowList(for level: MenuPanelLevel) -> some View {
        ScrollViewReader { proxy in
            scrollableRows(for: level)
                // Keyboard selection has to stay visible, including when it wraps from the last row
                // straight back to the first.
                .onChange(of: viewModel.selectedIdentifier) { _, identifier in
                    guard let identifier else {
                        return
                    }

                    proxy.scrollTo(identifier)
                }
        }
    }

    func scrollableRows(for level: MenuPanelLevel) -> some View {
        ScrollView {
            // A plain stack rather than a lazy one: a single menu level is small, and rendering it
            // eagerly keeps scroll-into-view working, which a `LazyVStack` breaks by not
            // materialising rows that are not on screen.
            VStack(alignment: .leading, spacing: 0) {
                ForEach(level.nodes) { node in
                    row(for: node)
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

    func row(for node: MenuNode) -> some View {
        MenuPanelRowView(node: node,
                         isSelected: viewModel.isSelected(node),
                         isAwaitingConfirmation: viewModel.isAwaitingConfirmation(node),
                         hoverChanged: { isHovering in
                             if isHovering {
                                 viewModel.select(node)
                             } else {
                                 viewModel.clearSelection(ifSelected: node)
                             }
                         },
                         activate: {
                             handleOutcome(viewModel.activateFromMouse(node))
                         })
                         .id(node.id)
    }
}

// MARK: - Keyboard

private extension MenuPanelView {
    /// Keys the search field handed over because the list wants them more than the caret does.
    func perform(_ command: MenuPanelSearchField.Command, in level: MenuPanelLevel) -> Bool {
        switch command {
        case .moveUp:
            viewModel.moveSelection(.up, in: level)
        case .moveDown:
            viewModel.moveSelection(.down, in: level)
        case .moveRight:
            guard let node = viewModel.selectedNode(in: level), node.isSubmenu else {
                return true
            }

            viewModel.enter(node)
        case .moveLeft:
            // At the top level this does nothing rather than dismissing: closing the panel is what
            // escape is for.
            guard level.depth > 0 else {
                return true
            }

            viewModel.leave(from: level)
        case let .activate(kind):
            guard let node = viewModel.selectedNode(in: level) else {
                return true
            }

            handleOutcome(viewModel.activateFromKeyboard(node, kind: kind))
        case .cancel:
            cancel()
        }

        return true
    }

    func cancel() {
        guard searchViewModel.cancel() == .shouldDismiss else {
            return
        }

        dismiss()
    }

    func queryChanged() {
        viewModel.applyQueryChange(isSearching: searchViewModel.hasQuery, resultLevel: currentLevel())
    }
}

// MARK: - Actions

private extension MenuPanelView {
    /// Picking a menu item closed the menu; picking a row closes the panel. Everything else leaves
    /// it open.
    func handleOutcome(_ outcome: MenuPanelActivationOutcome) {
        guard outcome == .performed else {
            return
        }

        searchViewModel.clear()
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
