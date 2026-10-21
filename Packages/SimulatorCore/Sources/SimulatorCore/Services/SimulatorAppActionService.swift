//
//  SimulatorAppActionService.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 05.09.26.
//

import Foundation
import os

/// App-scoped `simctl` actions, addressed by device UDID plus bundle identifier.
///
/// It exists with a single member because a restore has to stop the app before overwriting what it
/// is holding open. The rest of the per-app actions belong to that feature and extend this seam
/// rather than opening a second place that shells out to `simctl`.
protocol SimulatorAppActionServing: AnyObject, Sendable {
    /// Stops `bundleIdentifier` on `deviceUdid`.
    ///
    /// Throws only for a real failure. An app that is not running, and a device that is not booted,
    /// both already satisfy what the caller wanted and are reported as success.
    func terminateApp(bundleIdentifier: String, deviceUdid: String) async throws
}

final class SimulatorAppActionService: SimulatorAppActionServing, Sendable {
    /// Blocking work stays off the Swift concurrency cooperative pool — same reasoning as
    /// ``SimulatorCleanupService``'s work queue.
    private static let workQueue = DispatchQueue(
        label: "SimulatorAppActionService.workQueue",
        qos: .userInitiated
    )

    /// `simctl` reports both "nothing was running" cases as a failure. Neither is one: the caller
    /// asked for the app not to be running, and it is not running.
    private static let benignFailureFragments = [
        "found nothing to terminate",
        "unable to terminate",
        "no devices are booted",
        "current state: shutdown",
        "invalid device state"
    ]

    func terminateApp(bundleIdentifier: String, deviceUdid: String) async throws {
        do {
            let output = try await onWorkQueue {
                try Process.execute(command: "/usr/bin/xcrun",
                                    arguments: ["simctl", "terminate", deviceUdid, bundleIdentifier])
            }

            os_log("Terminated %{public}@ on %{public}@: %{public}@", bundleIdentifier, deviceUdid, output)
        } catch {
            guard Self.isBenignTerminationFailure(error) else {
                throw error
            }

            os_log("Nothing to terminate for %{public}@ on %{public}@", bundleIdentifier, deviceUdid)
        }
    }

    private static func isBenignTerminationFailure(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()

        return benignFailureFragments.contains { message.contains($0) }
    }

    private func onWorkQueue<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            Self.workQueue.async {
                continuation.resume(with: Result { try work() })
            }
        }
    }
}
