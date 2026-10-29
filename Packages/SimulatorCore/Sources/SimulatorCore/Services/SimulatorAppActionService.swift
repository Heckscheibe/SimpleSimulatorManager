//
//  SimulatorAppActionService.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 05.09.26.
//

import Foundation
import os

/// What stopping an app found.
public enum AppTerminationOutcome: Sendable, Equatable {
    case terminated
    /// The app was not running, or the device was not booted — already what the caller wanted.
    case notRunning
}

/// App-scoped `simctl` actions, addressed by device UDID plus bundle identifier.
///
/// It exists with a single member because a restore has to stop the app before overwriting what it
/// is holding open. The rest of the per-app actions belong to that feature and extend this seam
/// rather than opening a second place that shells out to `simctl`.
public protocol SimulatorAppActionServing: AnyObject, Sendable {
    /// Stops `bundleIdentifier` on `deviceUdid`.
    ///
    /// Throws only for a real failure. An app that is not running, and a device that is not booted,
    /// both already satisfy what the caller wanted and are reported as ``AppTerminationOutcome/notRunning``.
    @discardableResult
    func terminateApp(bundleIdentifier: String, deviceUdid: String) async throws -> AppTerminationOutcome
}

public final class SimulatorAppActionService: SimulatorAppActionServing, Sendable {
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

    public init() {}

    @discardableResult
    public func terminateApp(bundleIdentifier: String, deviceUdid: String) async throws -> AppTerminationOutcome {
        do {
            let output = try await Self.workQueue.perform {
                try Process.execute(command: "/usr/bin/xcrun",
                                    arguments: ["simctl", "terminate", deviceUdid, bundleIdentifier])
            }

            os_log("Terminated %{public}@ on %{public}@: %{public}@", bundleIdentifier, deviceUdid, output)

            return .terminated
        } catch {
            guard Self.isBenignTerminationFailure(error) else {
                throw error
            }

            os_log("Nothing to terminate for %{public}@ on %{public}@", bundleIdentifier, deviceUdid)

            return .notRunning
        }
    }

    private static func isBenignTerminationFailure(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()

        return benignFailureFragments.contains { message.contains($0) }
    }
}
