//
//  MockMenuFlyoutPresenter.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 06.09.26.
//

import AppKit
import SwiftUI
@testable import SimulatorManager

/// Records what the controller asked for, so the chain bookkeeping can be tested without putting
/// windows on screen.
@MainActor
final class MockMenuFlyoutPresenter: MenuFlyoutPresenting {
    struct Shown: Equatable {
        let index: Int
        let anchorRowFrame: CGRect
    }

    /// What the safe triangle is measured against. Set by a test to stand for an open flyout.
    var flyoutFrames: [CGRect] = []

    private(set) var shown: [Shown] = []
    private(set) var hiddenFromIndices: [Int] = []

    func show(
        atIndex index: Int,
        anchorRowFrame: CGRect,
        rootWindow: NSWindow,
        content: (@escaping (CGSize) -> Void) -> AnyView
    ) {
        // Built rather than discarded, so a content builder that traps on a level it should never be
        // asked for fails here rather than only in the app.
        _ = content { _ in }
        shown.append(Shown(index: index, anchorRowFrame: anchorRowFrame))
    }

    func hideFlyouts(fromIndex index: Int) {
        hiddenFromIndices.append(index)
    }
}
