//
//  UserDefaultsDomain.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 28.08.26.
//

import Foundation

/// A defaults domain inside a container's `Library/Preferences`.
///
/// `UserDefaults.standard` writes `<bundle identifier>.plist` and every `UserDefaults(suiteName:)`
/// writes `<suite name>.plist` beside it, so the file name without its extension *is* the domain —
/// exactly the string that was passed to `UserDefaults(suiteName:)`.
///
/// The menu and the export have to agree on which of them belong to the app, so the rule lives
/// here rather than in either of them.
enum UserDefaultsDomain {
    static let globalPreferences = ".GlobalPreferences"
    static let systemDomainPrefix = "com.apple."

    static func domain(ofPreferencesFileAt url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    /// Domains the OS wrote on the app's behalf are device rather than app state.
    static func isSystemManaged(_ domain: String) -> Bool {
        domain == globalPreferences || domain.hasPrefix(systemDomainPrefix)
    }

    /// The domains worth offering and exporting for a container.
    ///
    /// System-managed domains drop out, with two exceptions so nothing goes missing: the container's
    /// own domain always stays — an Apple app's domain *is* `com.apple.…` — and a container holding
    /// nothing else keeps everything it has.
    static func appDomains(in domains: [String], ownDomain: String) -> [String] {
        let appDomains = domains.filter { !isSystemManaged($0) || $0 == ownDomain }

        return (appDomains.isEmpty ? domains : appDomains).sorted()
    }
}
