//
//  MenuTreeBuilder+Snapshots.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 20.10.26.
//

import Foundation
import SimulatorCore

/// Save Snapshot to Folder, at the end of an app's submenu.
///
/// Needs the device as well as the app — the snapshot is of one install on one simulator, and its
/// name says which — which is why it is not part of the shortcut rows, which only know the app.
extension MenuTreeBuilder {
    func snapshotNodes(for app: any SimulatorApp, on device: Device, identifierPrefix prefix: String) -> [MenuNode] {
        guard let snapshotSaveViewModel, snapshotSaveViewModel.canSaveSnapshot(of: app) else {
            return []
        }

        let identifier = "\(prefix).saveSnapshot"
        let divider = MenuNode.divider(id: "\(prefix).snapshotDivider")

        // The save outlives the panel, so reopening it mid-save shows how far along it is — and
        // the row being informational is what stops the same save being started twice.
        if let progress = snapshotSaveViewModel.progress(for: app, on: device) {
            var progressNode = MenuNode.informational(id: "\(identifier).progress", title: Self.progressTitle(progress))
            progressNode.accessibilityTitle = "\(Self.progressTitle(progress)) of \(app.displayName) on \(device.name)"

            return [divider, progressNode]
        }

        var saveNode = MenuNode.action(id: identifier, title: Self.saveSnapshotTitle) {
            snapshotSaveViewModel.saveSnapshot(of: app, on: device)
        }
        saveNode.accessibilityTitle = Self.saveSnapshotAccessibilityTitle(for: app, on: device)

        return [divider, saveNode]
    }

    static func saveSnapshotAccessibilityTitle(for app: any SimulatorApp, on device: Device) -> String {
        "Save snapshot of \(app.displayName) on \(device.name) to folder"
    }

    static let saveSnapshotTitle = "Save Snapshot to Folder…"

    static func progressTitle(_ progress: Double) -> String {
        "Saving Snapshot… \(Int((progress * 100).rounded(.down)))%"
    }
}
