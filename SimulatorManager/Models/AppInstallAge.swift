//
//  AppInstallAge.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 28.10.26.
//

import Foundation

/// How old an app's install is, ready to draw.
///
/// Derived once per tree build by ``AppInstallAgeFormatter`` so a row only has to place the text it
/// is given. The strings are final: nothing downstream formats a date.
struct AppInstallAge: Hashable {
    /// Whether the install was the app arriving or the app being replaced. `nil` where the source
    /// does not know — an app listed under its device carries no change type — and the label then
    /// says only that it was installed.
    enum Kind: Hashable {
        case installed
        case updated
    }

    let kind: Kind?
    /// "3 days ago", abbreviated to fit beside a device name in a 300 pt panel.
    let relative: String
    /// The same instant, written out, for the submenu and for VoiceOver.
    let absolute: String
    /// Past the user's threshold. The row pairs this with an icon and the submenu with a sentence,
    /// so it never rests on colour alone.
    let isStale: Bool
    /// The threshold in force, so the submenu can say what "stale" meant when it was decided.
    let staleThreshold: TimeInterval
}

extension AppInstallAge {
    var accessibilityDescription: String {
        let verb =
            switch kind {
            case .installed: "installed"
            case .updated: "updated"
            case nil: "last installed"
            }

        return "\(verb) \(relative)" + (isStale ? ", stale" : "")
    }
}
