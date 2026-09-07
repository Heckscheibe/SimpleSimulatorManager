//
//  MenuFlyoutGeometryTests.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 06.09.26.
//

import Foundation
import Testing
@testable import SimulatorManager

/// Flyout placement is the part of the feature that is hardest to check by hand: reproducing it
/// means dragging the status item to the far right of the menu bar, or finding a submenu tall enough
/// to run off the bottom of the display. Both are ordinary situations, so both are pinned here.
@Suite("Menu flyout geometry")
struct MenuFlyoutGeometryTests {
    /// The measurement this was designed against: a 1728-wide display with the status item near the
    /// right, leaving 381 points beside the panel.
    private static let screen = CGRect(x: 0, y: 0, width: 1728, height: 1050)
    private static let panel = CGRect(x: 1047, y: 550, width: 300, height: 460)
    private static let size = CGSize(width: 300, height: 200)

    // MARK: - Coordinate spaces

    @Test("A row's frame in the window becomes its frame on screen")
    func rowFrameIsConvertedToScreenCoordinates() {
        // SwiftUI measures downwards from the top of the window; AppKit upwards from the bottom of
        // the display. Getting this backwards puts a flyout at the opposite end of the panel.
        let window = CGRect(x: 100, y: 200, width: 300, height: 400)
        let row = CGRect(x: 0, y: 50, width: 300, height: 22)

        let frame = MenuFlyoutGeometry.screenFrame(forRow: row, inWindow: window)

        #expect(frame.minX == 100)
        #expect(frame.maxY == 550)
        #expect(frame.height == 22)
    }

    // MARK: - Placement

    @Test("A flyout opens beside its window, with its first row level with the row that opened it")
    func flyoutOpensBesideTheWindow() {
        let anchor = CGRect(x: 1047, y: 900, width: 300, height: 22)

        let frame = Self.frame(anchoredTo: anchor)

        #expect(frame.minX == Self.panel.maxX - MenuFlyoutGeometry.overlap)
        // The inset is the flyout's own top padding, so the two rows line up rather than the flyout
        // starting a few points low.
        #expect(frame.maxY == anchor.maxY + MenuPanelStyle.listVerticalPadding)
    }

    @Test("A flyout with no room on the right opens to the left instead")
    func flyoutFlipsAtTheRightEdge() {
        // The status item dragged to the far right of the menu bar, which leaves 28 points beside a
        // 300-point panel.
        let panel = CGRect(x: 1400, y: 550, width: 300, height: 460)
        let anchor = CGRect(x: 1400, y: 900, width: 300, height: 22)

        let frame = MenuFlyoutGeometry.frame(ofSize: Self.size,
                                             anchoredTo: anchor,
                                             besideWindow: panel,
                                             onScreen: Self.screen,
                                             alignmentInset: MenuPanelStyle.listVerticalPadding)

        #expect(frame.maxX == panel.minX + MenuFlyoutGeometry.overlap)
        #expect(frame.minX >= Self.screen.minX)
    }

    @Test("A flyout taller than the room below its row is pushed back onto the screen")
    func flyoutStaysOnScreenVertically() {
        let anchor = CGRect(x: 1047, y: 120, width: 300, height: 22)
        let tall = CGSize(width: 300, height: 460)

        let frame = MenuFlyoutGeometry.frame(ofSize: tall,
                                             anchoredTo: anchor,
                                             besideWindow: Self.panel,
                                             onScreen: Self.screen,
                                             alignmentInset: MenuPanelStyle.listVerticalPadding)

        #expect(frame.minY == Self.screen.minY)
        #expect(frame.maxY <= Self.screen.maxY)
    }

    @Test("A flyout hanging off a row near the top of the screen stays under the menu bar")
    func flyoutStaysBelowTheTopOfTheScreen() {
        let anchor = CGRect(x: 1047, y: 1040, width: 300, height: 22)

        let frame = Self.frame(anchoredTo: anchor)

        #expect(frame.maxY == Self.screen.maxY)
    }

    // MARK: - Safe triangle

    @Test("A pointer moving diagonally towards an open flyout counts as heading into it")
    func diagonalMovementIsInsideTheTriangle() {
        let triangle = Self.triangle(apex: CGPoint(x: 1000, y: 500))

        // Below the row it left, but still aimed at the flyout — the move that drill-down never had
        // to survive and that a plain hover would interrupt.
        #expect(triangle?.contains(CGPoint(x: 1020, y: 480)) == true)
        #expect(triangle?.contains(CGPoint(x: 1020, y: 505)) == true)
    }

    @Test("A pointer moving away from the flyout is outside the triangle")
    func movementAwayIsOutsideTheTriangle() {
        let triangle = Self.triangle(apex: CGPoint(x: 1000, y: 500))

        // Straight down the panel: the user is picking another row, not travelling.
        #expect(triangle?.contains(CGPoint(x: 1000, y: 400)) == false)
        // Backwards, away from the flyout entirely.
        #expect(triangle?.contains(CGPoint(x: 960, y: 500)) == false)
        // Past the far side of the flyout.
        #expect(triangle?.contains(CGPoint(x: 1020, y: 700)) == false)
    }

    @Test("A flyout that flipped to the left is approached from the other side")
    func triangleFollowsAFlippedFlyout() {
        let apex = CGPoint(x: 1010, y: 500)
        let flipped = CGRect(x: 700, y: 300, width: 300, height: 220)
        let triangle = MenuFlyoutSafeTriangle(apex: apex, flyoutFrame: flipped)

        // The edge facing the pointer is the flyout's right one, so heading left is heading in.
        #expect(triangle?.contains(CGPoint(x: 1005, y: 495)) == true)
        #expect(triangle?.contains(CGPoint(x: 1020, y: 500)) == false)
    }

    @Test("There is no triangle without a flyout to protect")
    func noTriangleWithoutAFlyout() {
        #expect(MenuFlyoutSafeTriangle(apex: CGPoint(x: 1000, y: 500), flyoutFrame: .zero) == nil)
    }
}

private extension MenuFlyoutGeometryTests {
    static func frame(anchoredTo anchor: CGRect) -> CGRect {
        MenuFlyoutGeometry.frame(ofSize: size,
                                 anchoredTo: anchor,
                                 besideWindow: panel,
                                 onScreen: screen,
                                 alignmentInset: MenuPanelStyle.listVerticalPadding)
    }

    static func triangle(apex: CGPoint) -> MenuFlyoutSafeTriangle? {
        MenuFlyoutSafeTriangle(apex: apex, flyoutFrame: CGRect(x: 1043, y: 300, width: 300, height: 220))
    }
}
