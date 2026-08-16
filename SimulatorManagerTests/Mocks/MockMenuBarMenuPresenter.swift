//
//  MockMenuBarMenuPresenter.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 11.08.26.
//

import Foundation
@testable import SimulatorManager

@MainActor
class MockMenuBarMenuPresenter: MenuBarMenuPresenting {
    // MARK: - Call Tracking

    var openMenuCallCount = 0

    /// Controls whether the status item is considered reachable.
    var openMenuResult = true

    // MARK: - MenuBarMenuPresenting Implementation

    @discardableResult
    func openMenu() -> Bool {
        openMenuCallCount += 1

        return openMenuResult
    }
}
