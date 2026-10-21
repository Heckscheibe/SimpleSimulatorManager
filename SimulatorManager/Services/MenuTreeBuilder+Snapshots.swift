//
//  MenuTreeBuilder+Snapshots.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 20.10.26.
//

import Foundation
import SimulatorCore

/// Save Snapshot to Folder, at the end of an app's submenu: a submenu of what the snapshot holds.
///
/// Needs the device as well as the app — the snapshot is of one install on one simulator, and its
/// name says which — which is why it is not part of the shortcut rows, which only know the app.
///
/// Every option is always offered. Knowing which would find something means reading file headers,
/// which building the tree must never do; an option that finds nothing says so when it is picked.
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
            return [divider, .informational(id: "\(identifier).progress", title: Self.progressTitle(progress))]
        }

        let options = SnapshotSaveOption.allCases.map { option in
            let save = MenuActionItem(title: option.title) {
                snapshotSaveViewModel.saveSnapshot(of: app, on: device, contents: option.contents)
            }

            return MenuNode.action(id: "\(identifier).\(option.rawValue)",
                                   title: option.title,
                                   subtitle: option.subtitle,
                                   actions: [save])
        }

        return [divider, .submenu(id: identifier, title: Self.saveSnapshotTitle, children: options)]
    }

    static let saveSnapshotTitle = "Save Snapshot to Folder"

    static func progressTitle(_ progress: Double) -> String {
        "Saving Snapshot… \(Int((progress * 100).rounded(.down)))%"
    }
}

/// The rows under Save Snapshot to Folder, in the order they are listed. The raw value is the
/// row's identifier component.
enum SnapshotSaveOption: String, CaseIterable {
    case everything
    case databasesAndUserDefaults
    case databases
    case userDefaults

    var title: String {
        switch self {
        case .everything:
            "Everything"
        case .databasesAndUserDefaults:
            "Databases and UserDefaults"
        case .databases:
            "Databases Only"
        case .userDefaults:
            "UserDefaults Only"
        }
    }

    /// Restoring a synced Realm puts back only the local copy, which is easy to mistake for
    /// rolling back the server, so the row says so where it is picked.
    var subtitle: String? {
        switch self {
        case .databases:
            "SQLite and Realm. A synced Realm restores local state only."
        case .everything, .databasesAndUserDefaults, .userDefaults:
            nil
        }
    }

    var contents: SnapshotContents {
        switch self {
        case .everything:
            .everything
        case .databasesAndUserDefaults:
            .databasesAndUserDefaults
        case .databases:
            .databases
        case .userDefaults:
            .userDefaults
        }
    }
}
