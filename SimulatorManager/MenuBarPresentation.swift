//
//  MenuBarPresentation.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 05.09.26.
//

import Foundation

/// Which menu bar surface the app is built with: the original `NSMenu`, or the searchable panel.
///
/// The panel is the default. Define the `LEGACY_MENU_BAR` compilation condition — Build Settings →
/// *Swift Compiler – Custom Flags* → *Active Compilation Conditions* — to build the menu that
/// shipped instead. Nothing else has to change: both surfaces are driven by the same view models,
/// so the menu renders its per-view hierarchy and the panel renders the ``MenuNode`` tree that
/// describes the same thing.
///
/// **Why this is not a plain `Bool`.** It has to be a compile-time choice, twice over:
///
/// - `SceneBuilder` has no conditional support, so `if` cannot pick between two scenes.
/// - `.menuBarExtraStyle(.window)` and the default `.menu` style are *different types*, so the
///   modifier cannot be branched on either, and there is no type-erased `MenuBarExtraStyle`.
///
/// Declaring both scenes and selecting with `isInserted:` does not work: SwiftUI creates a status
/// item for every `MenuBarExtra` in the scene graph regardless, so the app grows a second menu bar
/// icon. That was measured, not assumed.
///
/// When the panel stops being provisional, delete this file, the `#if` in ``SimulatorManagerApp``,
/// and the views under `Views/` that only the menu uses.
enum MenuBarPresentation {
    /// For code outside the scene graph that needs to know which surface is live.
    static var usesSearchablePanel: Bool {
        #if LEGACY_MENU_BAR
            false
        #else
            true
        #endif
    }
}
