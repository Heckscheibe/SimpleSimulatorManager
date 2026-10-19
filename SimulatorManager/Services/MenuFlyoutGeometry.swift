//
//  MenuFlyoutGeometry.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 06.09.26.
//

import CoreGraphics

/// Where a flyout goes on screen.
///
/// Deliberately free of AppKit. Placement has to be right in exactly the cases that are tedious to
/// reproduce by hand — a status item at the far right of the screen with no room for a flyout, a
/// submenu taller than the space below the row it hangs off — so it is separated from the window
/// code and tested directly instead of being eyeballed once.
enum MenuFlyoutGeometry {
    /// How far a flyout overlaps the window it hangs off.
    ///
    /// Without it the pointer crosses a hairline of desktop on its way in, the hover lands on
    /// nothing, and the flyout it was heading for closes underneath it.
    static let overlap: CGFloat = 4

    /// Converts a row's frame in SwiftUI's window space — top-left origin, y growing downwards —
    /// into AppKit's screen space, where y grows upwards from the bottom of the display.
    static func screenFrame(forRow rowFrame: CGRect, inWindow windowFrame: CGRect) -> CGRect {
        CGRect(x: windowFrame.minX + rowFrame.minX,
               y: windowFrame.maxY - rowFrame.maxY,
               width: rowFrame.width,
               height: rowFrame.height)
    }

    /// The frame for a flyout of `size`, opened by the row at `anchor`.
    ///
    /// - Parameters:
    ///   - anchor: The opening row, in screen coordinates.
    ///   - windowFrame: The window the row is in — the panel, or the flyout one level up.
    ///   - visibleFrame: The screen area the flyout has to stay inside.
    ///   - alignmentInset: The flyout's own top padding, so its first row lines up with the row that
    ///     opened it rather than sitting a few points below it.
    ///   - prefersLeft: Whether the window this hangs off opened to the left of *its* parent. The
    ///     chain keeps going the way it started: a flyout to the right of one that flipped left
    ///     would land on top of the panel.
    static func frame(
        ofSize size: CGSize,
        anchoredTo anchor: CGRect,
        besideWindow windowFrame: CGRect,
        onScreen visibleFrame: CGRect,
        alignmentInset: CGFloat,
        prefersLeft: Bool = false
    ) -> CGRect {
        let rightX = windowFrame.maxX - overlap
        let leftX = windowFrame.minX + overlap - size.width
        var origin = CGPoint(x: prefersLeft ? leftX : rightX, y: anchor.maxY + alignmentInset - size.height)

        // The status item sits near the right of the menu bar, so running out of room on the right
        // is the normal case rather than the edge case. Flipping to the left of the parent is what
        // `NSMenu` did, and it overlaps the parent for the same reason: there is nowhere else to go.
        if prefersLeft {
            if origin.x < visibleFrame.minX {
                origin.x = rightX
            }
        } else if origin.x + size.width > visibleFrame.maxX {
            origin.x = leftX
        }

        origin.x = clamp(origin.x, lower: visibleFrame.minX, upper: visibleFrame.maxX - size.width)
        origin.y = clamp(origin.y, lower: visibleFrame.minY, upper: visibleFrame.maxY - size.height)

        return CGRect(origin: origin, size: size)
    }

    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        // A flyout larger than the screen would invert the bounds; keeping it pinned to the near
        // edge beats placing it off the far one.
        guard lower < upper else {
            return lower
        }

        return min(max(value, lower), upper)
    }
}

// MARK: - Safe triangle

/// The wedge between the row the pointer just left and the flyout it opened.
///
/// Moving diagonally from a row into its flyout crosses the rows in between, and each of those would
/// otherwise swap the flyout out from under the pointer before it arrives. `NSMenu` solved this by
/// ignoring hovers inside this triangle for a moment, and so does the panel.
struct MenuFlyoutSafeTriangle {
    let apex: CGPoint
    let baseTop: CGPoint
    let baseBottom: CGPoint

    /// - Parameters:
    ///   - apex: Where the pointer was when it left the row.
    ///   - flyoutFrame: The open flyout, in screen coordinates.
    ///   - tolerance: Extra height on the base, so a pointer aimed slightly past a corner still
    ///     counts as heading in.
    init?(apex: CGPoint, flyoutFrame: CGRect, tolerance: CGFloat = 12) {
        guard !flyoutFrame.isEmpty else {
            return nil
        }

        // The flyout may have been flipped to the left, in which case the edge facing the pointer is
        // its right one.
        let baseX = flyoutFrame.midX >= apex.x ? flyoutFrame.minX : flyoutFrame.maxX

        self.apex = apex
        baseTop = CGPoint(x: baseX, y: flyoutFrame.maxY + tolerance)
        baseBottom = CGPoint(x: baseX, y: flyoutFrame.minY - tolerance)
    }

    func contains(_ point: CGPoint) -> Bool {
        let first = Self.cross(point, apex, baseTop)
        let second = Self.cross(point, baseTop, baseBottom)
        let third = Self.cross(point, baseBottom, apex)
        let hasNegative = first < 0 || second < 0 || third < 0
        let hasPositive = first > 0 || second > 0 || third > 0

        // Inside means the point is on the same side of all three edges. A point on an edge gives
        // zero and belongs to both, which keeps the boundary inclusive.
        return !(hasNegative && hasPositive)
    }

    private static func cross(_ point: CGPoint, _ start: CGPoint, _ end: CGPoint) -> CGFloat {
        (point.x - end.x) * (start.y - end.y) - (start.x - end.x) * (point.y - end.y)
    }
}

// MARK: - Approach

/// Whether the pointer is still travelling into a flyout, as opposed to having stopped short of it.
///
/// Being inside the safe triangle is not enough on its own: a pointer that comes to rest there, or
/// slides down the panel inside it, has chosen the row it is on. What distinguishes a pointer on its
/// way into the flyout is that it keeps getting closer to the flyout's facing edge.
struct MenuFlyoutApproach {
    /// Movement smaller than this does not count as getting closer — a hand resting on a mouse or
    /// trackpad still jitters the pointer by a fraction of a point.
    static let minimumProgress: CGFloat = 0.5

    private let edgeX: CGFloat
    private var closestDistance: CGFloat = .infinity
    private var lastProgress: ContinuousClock.Instant?

    /// - Parameter edgeX: The x coordinate of the flyout's edge facing the pointer, in screen space.
    init(towardsEdgeAt edgeX: CGFloat) {
        self.edgeX = edgeX
    }

    mutating func record(_ pointer: CGPoint, at instant: ContinuousClock.Instant) {
        let distance = abs(edgeX - pointer.x)

        guard distance < closestDistance - Self.minimumProgress else {
            return
        }

        closestDistance = distance
        lastProgress = instant
    }

    /// Whether the pointer has gone `duration` without getting any closer.
    func hasStalled(at instant: ContinuousClock.Instant, after duration: Duration) -> Bool {
        guard let lastProgress else {
            return false
        }

        return lastProgress.duration(to: instant) >= duration
    }
}
