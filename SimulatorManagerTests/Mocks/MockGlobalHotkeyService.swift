//
//  MockGlobalHotkeyService.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 11.08.26.
//

import Foundation
@testable import SimulatorManager

@MainActor
class MockGlobalHotkeyService: GlobalHotkeyServing {
    // MARK: - Call Tracking

    var registeredShortcuts: [GlobalShortcut] = []
    var unregisterCallCount = 0

    /// When set, the next `register` call throws this error instead of succeeding.
    var errorToThrow: GlobalHotkeyError?

    private var handler: (@MainActor () -> Void)?

    var registeredShortcut: GlobalShortcut? {
        registeredShortcuts.last
    }

    // MARK: - GlobalHotkeyServing Implementation

    func register(_ shortcut: GlobalShortcut, handler: @escaping @MainActor () -> Void) throws {
        if let errorToThrow {
            throw errorToThrow
        }

        registeredShortcuts.append(shortcut)
        self.handler = handler
    }

    func unregister() {
        unregisterCallCount += 1
        handler = nil
    }

    // MARK: - Test Helpers

    /// Simulates the user pressing the registered shortcut.
    func simulateTrigger() {
        handler?()
    }
}
