//
//  GlobalHotkeyServiceTests.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 11.08.26.
//

import AppKit
import Carbon.HIToolbox
import Testing
@testable import SimulatorManager

/// Exercises the real Carbon registration rather than a mock, so a broken hotkey mechanism is
/// caught here instead of only showing up as "the shortcut does nothing" at runtime.
///
/// The combinations used below are deliberately obscure to avoid colliding with shortcuts the
/// developer machine already has registered.
@Suite("GlobalHotkeyService Tests")
@MainActor
struct GlobalHotkeyServiceTests {
    // MARK: - Registration

    @Test("A valid shortcut is accepted by Carbon")
    func validShortcutRegisters() throws {
        let service = GlobalHotkeyService()
        defer { service.unregister() }

        let shortcut = GlobalShortcut(keyCode: UInt16(kVK_F19),
                                      modifierFlags: [.control, .option, .shift, .command])

        try service.register(shortcut) {}
    }

    @Test("Re-registering replaces the previous shortcut")
    func reRegistrationReplacesPrevious() throws {
        let service = GlobalHotkeyService()
        defer { service.unregister() }

        try service.register(GlobalShortcut(keyCode: UInt16(kVK_F19),
                                            modifierFlags: [.control, .option, .shift, .command])) {}

        // Would fail with `alreadyInUse` if the first registration were still held.
        try service.register(GlobalShortcut(keyCode: UInt16(kVK_F19),
                                            modifierFlags: [.control, .option, .shift, .command])) {}
    }

    @Test("A shortcut can be registered again after being released")
    func registrationAfterUnregister() throws {
        let service = GlobalHotkeyService()
        defer { service.unregister() }

        let shortcut = GlobalShortcut(keyCode: UInt16(kVK_F18), modifierFlags: [.control, .option, .command])

        try service.register(shortcut) {}
        service.unregister()
        try service.register(shortcut) {}
    }

    @Test("Unregistering without a registration is harmless")
    func unregisterWithoutRegistration() {
        GlobalHotkeyService().unregister()
    }

    // MARK: - Validation

    @Test("A shortcut without a required modifier is rejected before touching Carbon", arguments: [
        NSEvent.ModifierFlags(),
        .shift
    ])
    func shortcutWithoutModifierIsRejected(modifiers: NSEvent.ModifierFlags) {
        let service = GlobalHotkeyService()
        let shortcut = GlobalShortcut(keyCode: UInt16(kVK_ANSI_S), modifierFlags: modifiers)

        #expect(throws: GlobalHotkeyError.missingModifier) {
            try service.register(shortcut) {}
        }
    }
}
