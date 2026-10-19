//
//  MenuFlyoutControllerTests.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 06.09.26.
//

import AppKit
import Foundation
import SwiftUI
import Testing
@testable import SimulatorManager

/// The timing rules a real menu has and a plain hover has not: submenus that do not open on the way
/// past, and a flyout that survives the rows between it and the pointer.
@Suite("MenuFlyoutController Tests")
@MainActor
struct MenuFlyoutControllerTests {
    // MARK: - Hover timing

    @Test("A submenu opens the moment the pointer lands on it")
    func submenuOpensImmediately() {
        let controller = Self.makeController(presenter: MockMenuFlyoutPresenter())
        let recorder = ChainRecorder(controller: controller)

        controller.hoverBegan(on: Self.submenu(id: "device-type"), depth: 0)

        // Synchronously, with nothing awaited: any wait at all leaves the previous flyout standing
        // beside a row the pointer has already left.
        #expect(recorder.opened == [ChainRecorder.Opened(identifier: "device-type", depth: 0)])
    }

    @Test("A submenu whose opening starts work opens just as promptly")
    func submenuWithSideEffectOpensImmediately() {
        let controller = Self.makeController(presenter: MockMenuFlyoutPresenter())
        let recorder = ChainRecorder(controller: controller)
        let node = Self.submenu(id: "cleanup", onEnter: {})

        controller.hoverBegan(on: node, depth: 0)

        // The cleanup scan runs in the background and only once, so it is no reason to make every
        // opening of its submenu wait.
        #expect(recorder.opened == [ChainRecorder.Opened(identifier: "cleanup", depth: 0)])
    }

    @Test("Moving between submenus swaps the flyout each time")
    func movingBetweenSubmenusSwapsTheFlyout() {
        let presenter = MockMenuFlyoutPresenter()
        let controller = Self.makeController(presenter: presenter)
        let recorder = ChainRecorder(controller: controller)

        presenter.flyoutFrames = [Self.openFlyout]
        controller.pointerLocation = { CGPoint(x: 1000, y: 500) }
        controller.hoverBegan(on: Self.submenu(id: "device-type"), depth: 0)
        controller.hoverEnded(on: Self.submenu(id: "device-type"), depth: 0)

        // Straight down the panel to the next row, rather than sideways towards the open flyout —
        // so the safe triangle has nothing to protect and this hover is the user picking a row.
        controller.pointerLocation = { CGPoint(x: 1000, y: 450) }
        controller.hoverBegan(on: Self.submenu(id: "other-device-type"), depth: 0)

        let expected = [
            ChainRecorder.Opened(identifier: "device-type", depth: 0),
            ChainRecorder.Opened(identifier: "other-device-type", depth: 0)
        ]

        #expect(recorder.opened == expected)
    }

    @Test("Landing on an ordinary row closes the flyouts beside its level")
    func ordinaryRowClosesTheChain() async {
        let controller = Self.makeController(presenter: MockMenuFlyoutPresenter())
        let recorder = ChainRecorder(controller: controller)

        controller.hoverBegan(on: Self.action(id: "settings"), depth: 0)
        await waitUntil { !recorder.closed.isEmpty }

        #expect(recorder.closed == [0])
        #expect(recorder.opened.isEmpty)
    }

    @Test("A click opens a submenu without waiting")
    func clickingOpensImmediately() {
        let controller = Self.makeController(presenter: MockMenuFlyoutPresenter())
        let recorder = ChainRecorder(controller: controller)

        controller.openImmediately(Self.submenu(id: "device"), depth: 1)

        #expect(recorder.opened == [ChainRecorder.Opened(identifier: "device", depth: 1)])
    }

    // MARK: - Safe triangle

    @Test("Rows crossed on the way into an open flyout do not swap it")
    func rowsUnderADiagonalMoveAreIgnored() async {
        let presenter = MockMenuFlyoutPresenter()
        let controller = Self.makeController(presenter: presenter)
        let recorder = ChainRecorder(controller: controller)

        // A protection long enough that this asserts what happens *during* it rather than racing the
        // moment it runs out. What happens then is the next test's job.
        controller.timing.safeTriangleGrace = .seconds(5)
        presenter.flyoutFrames = [Self.openFlyout]
        controller.pointerLocation = { CGPoint(x: 1000, y: 500) }
        // The pointer leaves the row that opened the flyout, heading for it.
        controller.hoverEnded(on: Self.submenu(id: "device-type"), depth: 0)

        // On its way it crosses a sibling — still moving, still getting closer. Without the triangle
        // this row's own submenu would open and take the destination off the screen before the
        // pointer reached it.
        controller.pointerLocation = Self.pointerHeadingIntoTheFlyout()
        controller.hoverBegan(on: Self.submenu(id: "other-device-type"), depth: 0)
        try? await Task.sleep(for: .milliseconds(120))

        #expect(recorder.opened.isEmpty)
        #expect(recorder.closed.isEmpty)
    }

    @Test("A row the pointer stops on is taken up without waiting out the protection")
    func aSuppressedHoverIsAppliedWhenThePointerStops() async {
        let presenter = MockMenuFlyoutPresenter()
        let controller = Self.makeController(presenter: presenter)
        let recorder = ChainRecorder(controller: controller)

        // Far longer than the test waits, so only the pointer stopping can explain the row being
        // taken up.
        controller.timing.safeTriangleGrace = .seconds(30)
        presenter.flyoutFrames = [Self.openFlyout]
        controller.pointerLocation = { CGPoint(x: 1000, y: 500) }
        controller.hoverEnded(on: Self.submenu(id: "device-type"), depth: 0)

        // The pointer stops inside the triangle rather than travelling through it: the user has
        // picked this row, and nothing else will arrive to say so.
        controller.pointerLocation = { CGPoint(x: 1020, y: 480) }
        controller.hoverBegan(on: Self.submenu(id: "other-device-type"), depth: 0)

        await waitUntil(timeout: .seconds(2)) { !recorder.opened.isEmpty }

        #expect(recorder.opened == [ChainRecorder.Opened(identifier: "other-device-type", depth: 0)])
    }

    @Test("A row is taken up the moment the pointer leaves the triangle")
    func aSuppressedHoverIsAppliedWhenThePointerLeavesTheTriangle() async {
        let presenter = MockMenuFlyoutPresenter()
        let controller = Self.makeController(presenter: presenter)
        let recorder = ChainRecorder(controller: controller)

        controller.timing.safeTriangleGrace = .seconds(30)
        controller.timing.safeTriangleStall = .seconds(30)
        presenter.flyoutFrames = [Self.openFlyout]
        controller.pointerLocation = { CGPoint(x: 1000, y: 500) }
        controller.hoverEnded(on: Self.submenu(id: "device-type"), depth: 0)

        controller.pointerLocation = { CGPoint(x: 1020, y: 480) }
        controller.hoverBegan(on: Self.submenu(id: "other-device-type"), depth: 0)
        #expect(recorder.opened.isEmpty)

        // Down the panel and away from the flyout: no longer heading into it.
        controller.pointerLocation = { CGPoint(x: 1005, y: 440) }

        await waitUntil(timeout: .seconds(2)) { !recorder.opened.isEmpty }

        #expect(recorder.opened == [ChainRecorder.Opened(identifier: "other-device-type", depth: 0)])
    }

    @Test("A row is taken up once the protection expires, even while the pointer keeps closing in")
    func aSuppressedHoverIsAppliedWhenTheProtectionRunsOut() async {
        let presenter = MockMenuFlyoutPresenter()
        let controller = Self.makeController(presenter: presenter)
        let recorder = ChainRecorder(controller: controller)

        controller.timing.safeTriangleStall = .seconds(30)
        presenter.flyoutFrames = [Self.openFlyout]
        controller.pointerLocation = { CGPoint(x: 1000, y: 500) }
        controller.hoverEnded(on: Self.submenu(id: "device-type"), depth: 0)

        controller.pointerLocation = Self.pointerHeadingIntoTheFlyout()
        controller.hoverBegan(on: Self.submenu(id: "other-device-type"), depth: 0)

        await waitUntil(timeout: .seconds(2)) { !recorder.opened.isEmpty }

        #expect(recorder.opened == [ChainRecorder.Opened(identifier: "other-device-type", depth: 0)])
    }

    @Test("Reaching the flyout itself is not held off")
    func rowsInsideTheFlyoutAreNotSuppressed() async {
        let presenter = MockMenuFlyoutPresenter()
        let controller = Self.makeController(presenter: presenter)
        let recorder = ChainRecorder(controller: controller)

        presenter.flyoutFrames = [Self.openFlyout]
        controller.pointerLocation = { CGPoint(x: 1000, y: 500) }
        controller.hoverEnded(on: Self.submenu(id: "device-type"), depth: 0)

        // A row inside the flyout is the destination, not an obstacle — even though the pointer is
        // still inside the triangle when it gets there.
        controller.pointerLocation = { CGPoint(x: 1050, y: 480) }
        controller.hoverBegan(on: Self.submenu(id: "device"), depth: 1)

        await waitUntil { !recorder.opened.isEmpty }

        #expect(recorder.opened == [ChainRecorder.Opened(identifier: "device", depth: 1)])
    }

    @Test("A keystroke drops whatever the pointer was about to do")
    func theKeyboardCancelsAPendingHover() async {
        let controller = Self.makeController(presenter: MockMenuFlyoutPresenter())
        let recorder = ChainRecorder(controller: controller)

        // Landing on an ordinary row is the only hover that still has anything pending, and the
        // keyboard taking over must not close a flyout it has just been asked to move into.
        controller.hoverBegan(on: Self.action(id: "settings"), depth: 0)
        controller.cancelPending()
        try? await Task.sleep(for: .milliseconds(120))

        #expect(recorder.closed.isEmpty)
    }

    // MARK: - Windows

    @Test("One flyout is shown per open path entry, and anything deeper is closed")
    func chainIsShownInOrder() {
        let presenter = MockMenuFlyoutPresenter()
        let controller = Self.makeController(presenter: presenter)
        let window = NSWindow()
        let deviceType = Self.submenu(id: "device-type")
        let device = Self.submenu(id: "device")

        controller.rowFrameChanged(CGRect(x: 0, y: 40, width: 300, height: 22), for: deviceType)
        controller.rowFrameChanged(CGRect(x: 0, y: 10, width: 300, height: 22), for: device)
        controller.synchronize(levels: Self.levels(count: 3),
                               path: ["device-type", "device"],
                               rootWindow: window) { _, _, _, _ in AnyView(EmptyView()) }

        #expect(presenter.shown.map(\.index) == [0, 1])
        #expect(presenter.shown[0].anchorRowFrame.minY == 40)
        #expect(presenter.shown[1].anchorRowFrame.minY == 10)
        #expect(presenter.hiddenFromIndices == [2])
    }

    @Test("A level whose row has not been laid out ends the chain rather than being drawn against nothing")
    func aMissingAnchorEndsTheChain() {
        let presenter = MockMenuFlyoutPresenter()
        let controller = Self.makeController(presenter: presenter)
        let window = NSWindow()

        controller.rowFrameChanged(CGRect(x: 0, y: 40, width: 300, height: 22), for: Self.submenu(id: "device-type"))
        controller.synchronize(levels: Self.levels(count: 3),
                               path: ["device-type", "device"],
                               rootWindow: window) { _, _, _, _ in AnyView(EmptyView()) }

        #expect(presenter.shown.map(\.index) == [0])
        #expect(presenter.hiddenFromIndices == [1])
    }

    @Test("Closing the panel keeps where its rows are, so opening it again still finds them")
    func resetKeepsRowFrames() {
        let presenter = MockMenuFlyoutPresenter()
        let controller = Self.makeController(presenter: presenter)
        let window = NSWindow()

        controller.rowFrameChanged(CGRect(x: 0, y: 40, width: 300, height: 22), for: Self.submenu(id: "device-type"))
        controller.reset()

        // Hiding the panel does not tear down the view inside it, so the rows are laid out at the
        // positions they already had and `onGeometryChange` — which reports a *change* — says
        // nothing. Forgetting the frames here left the second opening with nowhere to hang a flyout.
        controller.synchronize(levels: Self.levels(count: 2),
                               path: ["device-type"],
                               rootWindow: window) { _, _, _, _ in AnyView(EmptyView()) }

        #expect(presenter.shown.map(\.index) == [0])
    }

    @Test("With no panel there is nothing to hang a flyout off")
    func noPanelClosesEverything() {
        let presenter = MockMenuFlyoutPresenter()
        let controller = Self.makeController(presenter: presenter)

        controller.synchronize(levels: Self.levels(count: 2),
                               path: ["device-type"],
                               rootWindow: nil) { _, _, _, _ in AnyView(EmptyView()) }

        #expect(presenter.shown.isEmpty)
        #expect(presenter.hiddenFromIndices == [0])
    }

    @Test("Only rows that can anchor a flyout are remembered")
    func ordinaryRowFramesAreNotKept() {
        let presenter = MockMenuFlyoutPresenter()
        let controller = Self.makeController(presenter: presenter)
        let window = NSWindow()

        // An action row cannot open a submenu, and the panel reports every row it lays out.
        controller.rowFrameChanged(CGRect(x: 0, y: 40, width: 300, height: 22), for: Self.action(id: "settings"))
        controller.synchronize(levels: Self.levels(count: 2),
                               path: ["settings"],
                               rootWindow: window) { _, _, _, _ in AnyView(EmptyView()) }

        #expect(presenter.shown.isEmpty)
    }
}

// MARK: - Helpers

/// Records the chain changes the controller asks for, standing in for the view model.
@MainActor
private final class ChainRecorder {
    struct Opened: Equatable {
        let identifier: String
        let depth: Int
    }

    private(set) var opened: [Opened] = []
    private(set) var closed: [Int] = []

    init(controller: MenuFlyoutController) {
        controller.openFlyout = { [weak self] node, depth in
            self?.opened.append(Opened(identifier: node.id, depth: depth))
        }
        controller.closeFlyouts = { [weak self] depth in
            self?.closed.append(depth)
        }
    }
}

@MainActor
private extension MenuFlyoutControllerTests {
    /// The flyout the safe-triangle tests aim at, in screen coordinates.
    static let openFlyout = CGRect(x: 1043, y: 300, width: 300, height: 220)

    static func makeController(presenter: MockMenuFlyoutPresenter) -> MenuFlyoutController {
        let controller = MenuFlyoutController(presenter: presenter)

        // Short enough to keep the suite quick, long enough that "not yet" is still observable.
        controller.timing = MenuFlyoutController.Timing(close: .milliseconds(40),
                                                        safeTriangleGrace: .milliseconds(80),
                                                        safeTriangleStall: .milliseconds(40),
                                                        pointerSampling: .milliseconds(2))
        controller.pointerLocation = { .zero }

        return controller
    }

    static func submenu(id: String, onEnter: (@MainActor () -> Void)? = nil) -> MenuNode {
        .submenu(id: id, title: id, onEnter: onEnter, children: [.action(id: "\(id).child", title: "Child") {}])
    }

    static func action(id: String) -> MenuNode {
        .action(id: id, title: id) {}
    }

    static func levels(count: Int) -> [MenuPanelLevel] {
        (0 ..< count).map { depth in
            MenuPanelLevel(title: depth == 0 ? nil : "Level \(depth)", nodes: [], depth: depth)
        }
    }

    /// A pointer travelling diagonally into ``openFlyout`` at a steady 100 points a second, inside the
    /// triangle from (1000, 500) all the way. Driven by the clock rather than by how often it is
    /// read, so it keeps closing in for the whole of any wait in these tests.
    static func pointerHeadingIntoTheFlyout() -> () -> CGPoint {
        let start = ContinuousClock.now

        return {
            let elapsed = start.duration(to: .now)
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18

            return CGPoint(x: min(1010 + 100 * seconds, openFlyout.minX - 1), y: 480)
        }
    }
}
