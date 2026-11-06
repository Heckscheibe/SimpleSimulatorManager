//
//  MockAppUpdater.swift
//  SimulatorManagerTests
//

import Foundation
@testable import SimulatorManager

@MainActor
final class MockAppUpdater: AppUpdating {
    @Published var canCheckForUpdates = true
    @Published var pendingUpdateVersion: String?
    @Published var automaticallyChecksForUpdates = true

    private(set) var checkForUpdatesCount = 0

    func checkForUpdates() {
        checkForUpdatesCount += 1
    }
}

@MainActor
final class MockAppActivator: AppActivating {
    private(set) var activateCount = 0
    private(set) var deactivateCount = 0

    func activate() {
        activateCount += 1
    }

    func deactivate() {
        deactivateCount += 1
    }
}
