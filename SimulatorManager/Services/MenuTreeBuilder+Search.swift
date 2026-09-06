//
//  MenuTreeBuilder+Search.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 04.09.26.
//

import Foundation

/// Turns search hits into rows.
///
/// Results reuse ``MenuNode`` so the panel renders and activates them with exactly the machinery it
/// already has — one row view, one selection model, one activation path — rather than growing a
/// parallel one that could drift.
extension MenuTreeBuilder {
    func searchResultNodes(for results: [MenuSearchResult]) -> [MenuNode] {
        results.map { result in
            // Flat action rows rather than submenus: the filtered list is flat by design, and a
            // submenu would make Return drill in when it should open the hit.
            .action(id: "search.\(result.id)",
                    title: result.title,
                    subtitle: result.subtitle,
                    iconName: result.iconName,
                    actions: actions(for: result))
        }
    }

    private func actions(for result: MenuSearchResult) -> [MenuActionItem] {
        switch result.kind {
        case let .device(device):
            // Only the simulator's own folder: the per-device folders are guarded by filesystem
            // checks, and running those for every hit on every keystroke is exactly the cost this
            // layer has to avoid.
            return [
                MenuActionItem(title: "Simulator Folder") {
                    simulatorManagerViewModel.didSelectSimulatorFolder(for: device)
                }
            ]
        case let .app(app, _):
            // The open shortcuts only. Copying a path is a drill-down elsewhere, and results are a
            // flat list — there is nothing to drill into here.
            return openActions(for: app, handler: simulatorManagerViewModel)
        }
    }
}
