//
//  PreferencesWindowOpeningTests.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 19.10.26.
//

import Foundation
import Testing
@testable import SimulatorManager

/// Clicking Settings… in the panel took up to three clicks to show the window: the panel was closed
/// before the app asked to come to the front, and by then macOS no longer granted it, so the window
/// opened behind the frontmost app.
@Suite("Opening the preferences window from the panel")
@MainActor
struct PreferencesWindowOpeningTests {
    @Test("The app comes to the front and the window opens before the panel is closed")
    func activatesAndOpensBeforeDismissing() {
        var steps: [String] = []

        PreferencesWindow.openFromPanel(activate: { steps.append("activate") },
                                        openWindow: { steps.append("open window") },
                                        dismissPanel: { steps.append("dismiss panel") })

        #expect(steps == ["activate", "open window", "dismiss panel"])
    }
}
