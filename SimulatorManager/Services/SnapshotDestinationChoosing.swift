//
//  SnapshotDestinationChoosing.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 20.10.26.
//

import AppKit
import Foundation

/// A folder the user picked for a snapshot.
struct SnapshotDestinationChoice: Equatable {
    let url: URL
    /// The user also asked for this folder to be used from now on, without asking.
    let useAsDefault: Bool
}

/// Asks the user where to save a snapshot. Behind a protocol so the view model that decides *when*
/// to ask stays testable without putting a panel on screen.
@MainActor
protocol SnapshotDestinationChoosing: AnyObject {
    /// Brings the app to the front, so the folder picker does not open behind whatever the user
    /// was working in.
    ///
    /// Separate from ``chooseFolder(message:startingAt:offersUseAsDefault:)`` because of when it
    /// has to run: activation is only a request on current macOS, granted while the user is still
    /// interacting with the app — that is, synchronously inside the row's action, while the panel
    /// is still up. By the time the picker is shown the panel has gone and the request would be
    /// refused. See ``PreferencesWindow/openFromPanel(activate:openWindow:dismissPanel:)``.
    func bringAppForward()

    /// - Parameters:
    ///   - message: Shown in the picker, for instance to say why the configured folder could not
    ///     be used.
    ///   - offersUseAsDefault: Whether to offer "Use this folder by default".
    /// - Returns: The chosen folder, or `nil` when the user cancelled.
    func chooseFolder(message: String?, startingAt directoryURL: URL?, offersUseAsDefault: Bool) async -> SnapshotDestinationChoice?
}

@MainActor
final class OpenPanelSnapshotDestinationChooser: SnapshotDestinationChoosing {
    func bringAppForward() {
        NSApp.activate()
    }

    func chooseFolder(message: String?, startingAt directoryURL: URL?, offersUseAsDefault: Bool) async -> SnapshotDestinationChoice? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = directoryURL
        panel.message = message ?? "Choose a folder for app snapshots."
        panel.prompt = offersUseAsDefault ? "Save Snapshot" : "Choose"

        let useAsDefaultCheckbox = NSButton(checkboxWithTitle: "Use this folder by default", target: nil, action: nil)

        if offersUseAsDefault {
            useAsDefaultCheckbox.sizeToFit()
            panel.accessoryView = useAsDefaultCheckbox
            panel.isAccessoryViewDisclosed = true
        }

        NSApp.activate()

        // Modeless rather than `runModal`: the menu bar panel is tearing itself down while this
        // opens, and a nested modal run loop underneath that is asking for trouble.
        let response = await withCheckedContinuation { continuation in
            panel.begin { response in
                continuation.resume(returning: response)
            }
            panel.orderFrontRegardless()
        }

        guard response == .OK, let url = panel.url else {
            return nil
        }

        return SnapshotDestinationChoice(url: url,
                                         useAsDefault: offersUseAsDefault && useAsDefaultCheckbox.state == .on)
    }
}
