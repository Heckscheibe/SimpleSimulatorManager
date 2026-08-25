//
//  UserFacingErrorReporting.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 25.08.26.
//

import AppKit
import Foundation

/// Tells the user that an action they triggered from the menu failed.
///
/// The menu closes the moment an item is clicked, so there is no place left to show inline feedback
/// — the same reason ``AlertDestructiveActionConfirmer`` uses an alert. Behind a protocol so the
/// services that report failures stay testable.
@MainActor
protocol UserFacingErrorReporting: AnyObject {
    func report(title: String, message: String)
}

@MainActor
final class AlertErrorReporter: UserFacingErrorReporting {
    func report(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")

        // The menu is already gone, so bring the app forward rather than leaving the alert behind
        // whatever the user was working in.
        NSApp.activate(ignoringOtherApps: true)

        _ = alert.runModal()
    }
}
