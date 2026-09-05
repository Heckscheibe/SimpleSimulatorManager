//
//  UserDefaultsCopyMenuItems.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 28.08.26.
//

import Foundation
import SwiftUI

/// The Copy UserDefaults action for a container, shared by the app and app group menus.
///
/// A container usually holds several defaults domains — the app's own plus whatever suites its SDKs
/// created — so each one can be copied on its own. A container with a single domain keeps the flat
/// item instead: the common case should not grow a level of nesting for a menu with one entry.
struct UserDefaultsCopyMenuItems: View {
    let domains: [String]
    /// Copies one domain, or every domain when passed `nil`.
    let copy: (String?) -> Void

    var body: some View {
        if domains.count > 1 {
            Menu(Self.title) {
                Button("All Domains") {
                    copy(nil)
                }

                Divider()

                ForEach(domains, id: \.self) { domain in
                    Button(domain) {
                        copy(domain)
                    }
                }
            }
        } else if !domains.isEmpty {
            Button(Self.title) {
                copy(nil)
            }
        }
    }
}

private extension UserDefaultsCopyMenuItems {
    static let title = "Copy UserDefaults as JSON"
}
