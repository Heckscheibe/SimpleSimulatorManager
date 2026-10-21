//
//  SnapshotSaveViewModel.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 20.10.26.
//

import AppKit
import Foundation
import Observation
import os
import SimulatorCore

/// Save Snapshot to Folder: where the snapshot goes, and which saves are still running.
///
/// The save outlives the panel. Picking the row dismisses it, and so does the folder picker taking
/// key, so nothing here may depend on the panel still being up. A save in progress shows in the
/// app's row the next time the panel opens, which also stops it from being started twice.
@MainActor
@Observable
final class SnapshotSaveViewModel {
    /// The fraction completed of each save in flight, keyed by ``key(for:on:)``. Present from the
    /// moment the row is picked, including while the user is choosing a folder.
    private(set) var progressByKey: [String: Double] = [:]

    @ObservationIgnored private let saver: AppSnapshotSaving
    @ObservationIgnored private let settings: Settings
    @ObservationIgnored private let destinationChooser: SnapshotDestinationChoosing
    @ObservationIgnored private let errorReporter: UserFacingErrorReporting
    @ObservationIgnored private let revealInFinder: @MainActor (URL) -> Void
    /// Where the picker opens when there is no default folder: wherever the user went last time.
    @ObservationIgnored private var lastChosenFolder: URL?
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]

    init(
        saver: AppSnapshotSaving = AppSnapshotSaveService(),
        settings: Settings,
        destinationChooser: SnapshotDestinationChoosing = OpenPanelSnapshotDestinationChooser(),
        errorReporter: UserFacingErrorReporting = AlertErrorReporter(),
        revealInFinder: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
    ) {
        self.saver = saver
        self.settings = settings
        self.destinationChooser = destinationChooser
        self.errorReporter = errorReporter
        self.revealInFinder = revealInFinder
    }

    /// Whether the app has anything a snapshot could capture, so the row is not offered for an app
    /// that would only produce an error.
    func canSaveSnapshot(of app: any SimulatorApp) -> Bool {
        app.appDocumentsFolderURL != nil
    }

    /// `nil` when no save of this app on this device is running.
    func progress(for app: any SimulatorApp, on device: Device) -> Double? {
        progressByKey[Self.key(for: app, on: device)]
    }

    /// - Parameter contents: What the snapshot holds. One save per app and device runs at a time,
    ///   whatever its contents, since the row's progress stands in for all four choices.
    func saveSnapshot(of app: any SimulatorApp, on device: Device, contents: SnapshotContents = .everything) {
        let key = Self.key(for: app, on: device)

        guard progressByKey[key] == nil else {
            return
        }
        guard let target = AppSnapshotTarget(app: app, device: device) else {
            errorReporter.report(title: Self.failureTitle(for: app.displayName),
                                 message: "The app has no data container to snapshot.")

            return
        }

        let configuredFolder = settings.snapshotExportFolder

        if configuredFolder == nil {
            // Now, while the panel is still up — see `bringAppForward`.
            destinationChooser.bringAppForward()
        }

        progressByKey[key] = 0
        tasks[key] = Task { [weak self] in
            await self?.save(target, contents: contents, appName: app.displayName, into: configuredFolder, key: key)
            self?.finish(key)
        }
    }

    /// Lets a test wait for every save it started.
    func waitForPendingSaves() async {
        for task in tasks.values {
            await task.value
        }
    }

    static func key(for app: any SimulatorApp, on device: Device) -> String {
        "\(device.udid).\(app.installIdentifier)"
    }
}

private extension SnapshotSaveViewModel {
    func save(
        _ target: AppSnapshotTarget,
        contents: SnapshotContents,
        appName: String,
        into configuredFolder: URL?,
        key: String
    ) async {
        var folder = configuredFolder
        var pickerMessage: String?

        while true {
            if folder == nil {
                guard let chosen = await chooseFolder(message: pickerMessage) else {
                    return
                }

                folder = chosen
            }

            guard let destination = folder else {
                return
            }

            do {
                let savedURL = try await saver.saveSnapshot(of: target,
                                                            into: destination,
                                                            contents: contents,
                                                            includeCaches: settings.includeCachesInSnapshots) { [weak self] fraction in
                    Task { @MainActor [weak self] in
                        self?.updateProgress(fraction, key: key)
                    }
                }

                revealInFinder(savedURL)

                return
            } catch let error as AppSnapshotSaveError {
                // The folder is the problem, not the app. Ask for another rather than quietly
                // saving somewhere the user did not pick.
                os_log("Snapshot destination unusable: %{public}@", error.localizedDescription)
                pickerMessage = "\(error.localizedDescription) Choose another folder for the snapshot of \(appName)."
                folder = nil
                destinationChooser.bringAppForward()
            } catch {
                os_log("Failed to save snapshot of %{public}@: %{public}@", appName, error.localizedDescription)
                errorReporter.report(title: Self.failureTitle(for: appName), message: error.localizedDescription)

                return
            }
        }
    }

    func chooseFolder(message: String?) async -> URL? {
        let startingAt = lastChosenFolder ?? Settings.defaultSnapshotExportFolder

        guard let choice = await destinationChooser.chooseFolder(message: message,
                                                                 startingAt: startingAt,
                                                                 offersUseAsDefault: true) else {
            return nil
        }

        lastChosenFolder = choice.url

        if choice.useAsDefault {
            settings.snapshotExportFolder = choice.url
        }

        return choice.url
    }

    /// Whole percents only: progress arrives per file, and redrawing the menu for every one of a
    /// container's thousands of files buys nothing anyone can see.
    func updateProgress(_ fraction: Double, key: String) {
        // A late report from a save that already finished must not bring its row back.
        guard let current = progressByKey[key] else {
            return
        }

        let rounded = (fraction * 100).rounded(.down) / 100

        if rounded > current {
            progressByKey[key] = rounded
        }
    }

    func finish(_ key: String) {
        progressByKey[key] = nil
        tasks[key] = nil
    }

    static func failureTitle(for appName: String) -> String {
        "Could not save a snapshot of \(appName)"
    }
}
