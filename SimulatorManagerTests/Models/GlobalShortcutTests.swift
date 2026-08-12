//
//  GlobalShortcutTests.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 11.08.26.
//

import AppKit
import Carbon.HIToolbox
import Testing
@testable import SimulatorManager

@Suite("GlobalShortcut Tests")
struct GlobalShortcutTests {
    // MARK: - Modifier Requirements

    @Test("A shortcut with ⌘, ⌥ or ⌃ satisfies the modifier requirement", arguments: [
        NSEvent.ModifierFlags.command,
        .option,
        .control,
        [.control, .option, .command],
        [.shift, .command]
    ])
    func requiredModifierIsSatisfied(modifiers: NSEvent.ModifierFlags) {
        let shortcut = GlobalShortcut(keyCode: UInt16(kVK_ANSI_S), modifierFlags: modifiers)

        #expect(shortcut.hasRequiredModifier, "Expected \(modifiers) to be a valid modifier combination")
    }

    @Test("A shortcut without ⌘, ⌥ or ⌃ is rejected", arguments: [
        NSEvent.ModifierFlags(),
        .shift,
        .capsLock,
        [.shift, .capsLock]
    ])
    func requiredModifierIsMissing(modifiers: NSEvent.ModifierFlags) {
        let shortcut = GlobalShortcut(keyCode: UInt16(kVK_ANSI_S), modifierFlags: modifiers)

        #expect(!shortcut.hasRequiredModifier, "Expected \(modifiers) to be rejected as a shortcut modifier")
    }

    // MARK: - Normalisation

    @Test("Irrelevant modifiers are discarded")
    func irrelevantModifiersAreDiscarded() {
        let shortcut = GlobalShortcut(keyCode: UInt16(kVK_ANSI_S),
                                      modifierFlags: [.command, .capsLock, .function, .numericPad])

        #expect(shortcut.modifierFlags == .command)
    }

    @Test("Shortcuts differing only in irrelevant modifiers are equal")
    func normalisationMakesShortcutsEqual() {
        let plain = GlobalShortcut(keyCode: UInt16(kVK_ANSI_S), modifierFlags: [.command])
        let noisy = GlobalShortcut(keyCode: UInt16(kVK_ANSI_S), modifierFlags: [.command, .capsLock])

        #expect(plain == noisy)
    }

    // MARK: - Carbon Translation

    @Test("Modifier flags translate to the matching Carbon mask")
    func carbonModifiersAreTranslated() {
        let shortcut = GlobalShortcut(keyCode: UInt16(kVK_ANSI_S),
                                      modifierFlags: [.control, .option, .command, .shift])
        let expected = UInt32(controlKey) | UInt32(optionKey) | UInt32(cmdKey) | UInt32(shiftKey)

        #expect(shortcut.carbonModifiers == expected)
    }

    @Test("An empty modifier set produces an empty Carbon mask")
    func emptyCarbonModifiers() {
        let shortcut = GlobalShortcut(keyCode: UInt16(kVK_ANSI_S), modifierFlags: [])

        #expect(shortcut.carbonModifiers == 0)
    }

    // MARK: - Display

    @Test("Modifiers are rendered in the canonical macOS order")
    func modifierOrderIsCanonical() {
        let shortcut = GlobalShortcut(keyCode: UInt16(kVK_ANSI_S),
                                      modifierFlags: [.command, .shift, .option, .control])

        #expect(shortcut.modifierDisplayString == "⌃⌥⇧⌘")
    }

    @Test("Special keys use their glyph", arguments: [
        (UInt16(kVK_Space), "Space"),
        (UInt16(kVK_Return), "↩"),
        (UInt16(kVK_Escape), "⎋"),
        (UInt16(kVK_Delete), "⌫"),
        (UInt16(kVK_LeftArrow), "←"),
        (UInt16(kVK_F5), "F5")
    ])
    func specialKeyNames(keyCode: UInt16, expected: String) {
        #expect(GlobalShortcut.keyName(for: keyCode) == expected)
    }

    @Test("The display string combines modifiers and key")
    func displayStringCombinesParts() {
        let shortcut = GlobalShortcut(keyCode: UInt16(kVK_Space), modifierFlags: [.control, .option])

        #expect(shortcut.displayString == "⌃⌥Space")
    }

    // MARK: - Default

    @Test("The default shortcut is ⌃⌥⌘ plus a printable key")
    func defaultShortcutIsValid() {
        let shortcut = GlobalShortcut.default

        #expect(shortcut.modifierFlags == [.control, .option, .command])
        #expect(shortcut.hasRequiredModifier)
        #expect(shortcut.keyCode == UInt16(kVK_ANSI_S))
    }

    // MARK: - Codable

    @Test("A shortcut survives an encode/decode round trip")
    func codableRoundTrip() throws {
        let original = GlobalShortcut(keyCode: UInt16(kVK_ANSI_S), modifierFlags: [.control, .option, .command])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GlobalShortcut.self, from: data)

        #expect(decoded == original)
        #expect(decoded.carbonModifiers == original.carbonModifiers)
    }

    // MARK: - Event Initialisation

    @Test("A shortcut is built from a key down event")
    func initialisationFromKeyDownEvent() throws {
        let event = try #require(NSEvent.keyEvent(with: .keyDown,
                                                  location: .zero,
                                                  modifierFlags: [.control, .option, .command],
                                                  timestamp: 0,
                                                  windowNumber: 0,
                                                  context: nil,
                                                  characters: "s",
                                                  charactersIgnoringModifiers: "s",
                                                  isARepeat: false,
                                                  keyCode: UInt16(kVK_ANSI_S)))
        let shortcut = try #require(GlobalShortcut(event: event))

        #expect(shortcut.keyCode == UInt16(kVK_ANSI_S))
        #expect(shortcut.modifierFlags == [.control, .option, .command])
    }

    @Test("A key up event does not produce a shortcut")
    func initialisationIgnoresKeyUpEvent() throws {
        let event = try #require(NSEvent.keyEvent(with: .keyUp,
                                                  location: .zero,
                                                  modifierFlags: [.command],
                                                  timestamp: 0,
                                                  windowNumber: 0,
                                                  context: nil,
                                                  characters: "s",
                                                  charactersIgnoringModifiers: "s",
                                                  isARepeat: false,
                                                  keyCode: UInt16(kVK_ANSI_S)))

        #expect(GlobalShortcut(event: event) == nil)
    }
}
