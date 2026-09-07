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
/// submenus, arrow navigation, dismissal — is rebuilt here.
///
/// Submenus open as flyouts beside the panel rather than replacing the level in place. Reaching an
/// app's Documents Folder is device type → device → app → action, and a drill-down made that four
/// screens with no sight of where you came from; as flyouts it is one continuous hover.
///
/// The tree is rebuilt on every render rather than captured when the panel opens, so state that
/// arrives while it is open (an app installed in a running simulator, a finished cleanup) lands in
/// the panel — and in any flyout hanging off it — instead of being frozen out of both.
struct MenuPanelView: View {
    let simulatorManagerViewModel: SimulatorManagerViewModel
    let settingsViewModel: SettingsViewModel
    let cleanupViewModel: CleanupSimulatorsViewModel
    let resetViewModel: ResetSimulatorsViewModel
    @ObservedObject var settings: Settings
    @ObservedObject var githubService: GithubService
    /// Closing the panel is the same status-item operation as opening it, so it goes through the
    /// abstraction that already isolates that from the rest of the app. It also hands over the
    /// panel's window, which is what the flyouts are positioned against.
    let menuPresenter: any MenuBarMenuPresenting
    @Bindable var searchViewModel: MenuSearchViewModel

    @Environment(\.openWindow) private var openWindow
    @State private var viewModel = MenuPanelViewModel()
    @State private var flyouts = MenuFlyoutController()
    @State private var listHeight: CGFloat = MenuPanelStyle.rowMinimumHeight

    var body: some View {
        let levels = currentLevels()
        let rootLevel = levels[0]

        VStack(alignment: .leading, spacing: 0) {
            MenuPanelSearchField(query: $searchViewModel.query,
                                 placeholder: "Search simulators and apps") { command in
                perform(command, in: currentLevel())
            }
            .padding(.horizontal, MenuPanelStyle.horizontalInset + 3)
            .padding(.vertical, MenuPanelStyle.listVerticalPadding + 2)

            Divider()

            if showsEmptyState(for: rootLevel) {
                MenuPanelEmptyStateView(query: searchViewModel.query)
            } else {
                rowList(for: rootLevel)
            }
        }
        .frame(width: MenuPanelStyle.width)
        .background(shortcuts)
        .background(MenuFlyoutSynchronizer {
            synchronizeFlyouts(levels: levels)
        })
        .onAppear {
            connectFlyouts()
        }
        .onChange(of: searchViewModel.query) { _, _ in
            queryChanged()
        }
        .onChange(of: searchViewModel.results.count) { _, count in
            announceResultCount(count)
        }
        .onDisappear {
            // Reopening starts at the top level, with nothing selected and an empty query — the way
            // reopening a menu does. The flyouts go with it: their windows are positioned against a
            // panel that is no longer there.
            flyouts.reset()
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
    /// The levels on screen: the ranked hits while there is a query, and the browsable menu when
    /// there is not. Both go through the same resolution, so one renderer, one selection model and
    /// one activation path serve both modes.
    func currentLevels() -> [MenuPanelLevel] {
        viewModel.levels(in: searchViewModel.hasQuery ? searchResultNodes() : makeNodes())
    }

    /// The level the keyboard works in: the deepest flyout, or the panel when none is open.
    func currentLevel() -> MenuPanelLevel {
        viewModel.level(in: searchViewModel.hasQuery ? searchResultNodes() : makeNodes())
    }

    /// A query that matched nothing gets an explanation rather than a blank panel.
    func showsEmptyState(for level: MenuPanelLevel) -> Bool {
        searchViewModel.hasQuery && level.nodes.isEmpty
    }

    /// VoiceOver gets no hint from a list changing under it, and the search field keeps focus, so
    /// the count is announced explicitly.
    func announceResultCount(_ count: Int) {
        guard searchViewModel.hasQuery else {
            return
        }

        let announcement = count == 1 ? "1 result" : "\(count) results"

        NSAccessibility.post(element: NSApp as Any,
                             notification: .announcementRequested,
                             userInfo: [
                                 .announcement: announcement,
                                 .priority: NSAccessibilityPriorityLevel.medium.rawValue
                             ])
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
            MenuNodeRowsView(nodes: level.nodes, handlers: handlers(atDepth: level.depth))
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
        .frame(height: listFrameHeight)
        .scrollBounceBehavior(.basedOnSize)
    }

    /// A `ScrollView` has no intrinsic height, and the window a `MenuBarExtra` puts it in imposes
    /// none — left to itself the panel collapses to a ten-point sliver. So the rows are measured and
    /// the panel sized to them, capped so that a machine with dozens of simulators gets a scrolling
    /// panel instead of one taller than the screen. While a query is live the list also gets a
    /// floor, so the panel does not jump on every keystroke that changes the number of hits.
    var listFrameHeight: CGFloat {
        let floor = searchViewModel.hasQuery
            ? MenuPanelStyle.searchResultsMinimumHeight
            : MenuPanelStyle.rowMinimumHeight

        return min(max(listHeight, floor), MenuPanelStyle.maximumListHeight)
    }

    /// Rows behave the same wherever they are drawn — the difference between the panel and a flyout
    /// is only which level they belong to.
    func handlers(atDepth depth: Int) -> MenuRowHandlers {
        MenuRowHandlers(depth: depth,
                        isHighlighted: viewModel.isHighlighted,
                        isAwaitingConfirmation: viewModel.isAwaitingConfirmation,
                        hoverChanged: { node, isHovering in
                            hoverChanged(isHovering, on: node, atDepth: depth)
                        },
                        frameChanged: { node, frame in
                            flyouts.rowFrameChanged(frame, for: node)
                        },
                        activate: { node in
                            activateFromMouse(node, atDepth: depth)
                        })
    }
}

// MARK: - Flyouts

private extension MenuPanelView {
    /// Wires the hover timing to the open path. Both live for as long as the panel does, so this
    /// happens once rather than on every render.
    func connectFlyouts() {
        flyouts.openFlyout = { node, depth in
            viewModel.openFlyout(for: node, atDepth: depth)
            showChain()
        }
        flyouts.closeFlyouts = { depth in
            viewModel.closeFlyouts(deeperThan: depth)
            showChain()
        }
    }

    /// Puts the chain on screen now rather than at the panel's next render.
    ///
    /// The open path changes synchronously under the pointer, but the windows follow it through a
    /// SwiftUI render, and waiting for that costs a frame — which is precisely what a submenu
    /// opening late looks like. Measured on a real install, the work itself is around seven
    /// milliseconds; the lag was never the computation, it was the wait for the next pass.
    func showChain() {
        synchronizeFlyouts(levels: currentLevels())
    }

    func synchronizeFlyouts(levels: [MenuPanelLevel]) {
        flyouts.synchronize(levels: levels,
                            path: viewModel.pathIdentifiers,
                            rootWindow: menuPresenter.panelWindow()) { depth, level, reportSize in
            AnyView(MenuFlyoutContentView(nodes: level.nodes,
                                          handlers: handlers(atDepth: depth),
                                          sizeChanged: reportSize))
        }
    }

    /// Hover drives both the highlight and the flyouts, so they can never disagree about which row
    /// the pointer is on.
    func hoverChanged(_ isHovering: Bool, on node: MenuNode, atDepth depth: Int) {
        guard isHovering else {
            viewModel.clearSelection(ifSelected: node)
            flyouts.hoverEnded(on: node, depth: depth)

            return
        }

        viewModel.select(node)
        flyouts.hoverBegan(on: node, depth: depth)
    }

    /// Clicking a submenu opens it without waiting out the hover delay, the way clicking one in a
    /// menu did. Anything else runs, and takes the whole panel with it.
    func activateFromMouse(_ node: MenuNode, atDepth depth: Int) {
        guard !node.isSubmenu else {
            flyouts.openImmediately(node, depth: depth)

            return
        }

        handleOutcome(viewModel.activateFromMouse(node))
    }
}

/// Pushes the flyout chain into its windows on every render of the panel.
///
/// SwiftUI has no hook for "the body ran"; an `NSViewRepresentable` is updated exactly then, which
/// is what keeps an open flyout in step with a tree that changed underneath it. The work is
/// deferred off the layout pass, because moving windows during one is not something AppKit expects.
private struct MenuFlyoutSynchronizer: NSViewRepresentable {
    let synchronize: () -> Void

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async(execute: synchronize)
    }
}

// MARK: - Keyboard

private extension MenuPanelView {
    /// Keys the search field handed over because the list wants them more than the caret does.
    func perform(_ command: MenuPanelSearchField.Command, in level: MenuPanelLevel) -> Bool {
        // The keyboard has taken over, so a submenu the pointer was hovering towards is no longer
        // what the user is asking for.
        flyouts.cancelPending()

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
            showChain()
        case .moveLeft:
            // At the top level this does nothing rather than dismissing: closing the panel is what
            // escape is for.
            guard level.depth > 0 else {
                return true
            }

            viewModel.leave(from: level)
            showChain()
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
        // Results are a flat list, so the chain has just been emptied and its windows are hanging
        // off rows that are no longer there.
        showChain()
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
