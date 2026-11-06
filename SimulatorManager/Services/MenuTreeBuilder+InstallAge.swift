//
//  MenuTreeBuilder+InstallAge.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 28.10.26.
//

import Foundation
import SimulatorCore

/// The install date of an app row: the short age drawn on the row, and the written-out dates at the
/// bottom of its submenu.
///
/// Both come from the bundle's modification date. The container's date is deliberately not used for
/// "installed" — it moves whenever the running app writes — and is shown, labelled, as the time the
/// app was last active.
extension MenuTreeBuilder {
    static let sharedAgeFormatter = AppInstallAgeFormatter()

    /// `nil` when ages are switched off or the app has no readable bundle date.
    func installAge(for app: any SimulatorApp, changeType: ChangeType?) -> AppInstallAge? {
        guard settings.showInstallAge else {
            return nil
        }

        return ageFormatter.age(for: app,
                                changeType: changeType,
                                now: now,
                                staleAfter: settings.staleAfterInterval)
    }

    /// The dates at the bottom of an app's submenu, behind a rule — or nothing, so an app without a
    /// date does not get a rule with nothing under it. They go last so the actions keep the positions
    /// they have in every other app's submenu.
    func ageNodes(for app: any SimulatorApp, age: AppInstallAge?, identifierPrefix prefix: String) -> [MenuNode] {
        guard let age, let bundleDate = app.bundleModifiedAt else {
            return []
        }

        let label =
            switch age.kind {
            case .installed: String(localized: "Installed")
            case .updated: String(localized: "Updated")
            case nil: String(localized: "Last installed")
            }
        var nodes: [MenuNode] = [
            .divider(id: "\(prefix).age.divider"),
            .informational(id: "\(prefix).age.installed", title: "\(label): \(ageFormatter.absolute(bundleDate))")
        ]

        // Only worth a line when it says something the first one does not.
        if let activeDate = app.contentModifiedAt, activeDate.timeIntervalSince(bundleDate) >= 60 {
            nodes.append(.informational(id: "\(prefix).age.active",
                                        title: String(localized: "Last active: \(ageFormatter.absolute(activeDate))")))
        }

        if age.isStale {
            // Says what the row above says: an updated app is "updated more than N days ago".
            let threshold = AppInstallAgeFormatter.dayCount(of: age.staleThreshold)
            let title =
                switch age.kind {
                case .updated: String(localized: "Stale: updated more than \(threshold) ago")
                case .installed, nil: String(localized: "Stale: installed more than \(threshold) ago")
                }

            nodes.append(.informational(id: "\(prefix).age.stale", title: title))
        }

        return nodes
    }
}
