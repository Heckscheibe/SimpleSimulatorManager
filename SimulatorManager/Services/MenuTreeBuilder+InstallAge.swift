//
//  MenuTreeBuilder+InstallAge.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 28.10.26.
//

import Foundation
import SimulatorCore

/// The install date of an app row: the short age drawn on the row, and the written-out dates at the
/// top of its submenu.
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
            case .installed: "Installed"
            case .updated: "Updated"
            case nil: "Last installed"
            }
        var nodes: [MenuNode] = [
            .divider(id: "\(prefix).age.divider"),
            .informational(id: "\(prefix).age.installed", title: "\(label): \(ageFormatter.absolute(bundleDate))")
        ]

        // Only worth a line when it says something the first one does not.
        if let activeDate = app.contentModifiedAt, activeDate.timeIntervalSince(bundleDate) >= 60 {
            nodes.append(.informational(id: "\(prefix).age.active",
                                        title: "Last active: \(ageFormatter.absolute(activeDate))"))
        }

        if age.isStale {
            nodes.append(.informational(id: "\(prefix).age.stale",
                                        title: "Stale: installed more than \(Self.dayCount(settings.staleAfterDays)) ago"))
        }

        return nodes
    }

    private static func dayCount(_ days: Int) -> String {
        days == 1 ? "1 day" : "\(days) days"
    }
}
