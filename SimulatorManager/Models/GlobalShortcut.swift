//
//  GlobalShortcut.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 11.08.26.
//

import AppKit
import Carbon.HIToolbox
import Foundation

/// A user configurable, system wide keyboard shortcut.
///
/// The physical key is stored as a virtual key code because that is what `RegisterEventHotKey`
/// expects and because key codes are keyboard layout independent. The human readable form is
/// resolved against the *current* layout, so a shortcut keeps reading correctly when the user
/// switches between QWERTY and QWERTZ.
struct GlobalShortcut: Equatable, Codable {
    /// Virtual key code as reported by `NSEvent.keyCode`.
    let keyCode: UInt16

    /// Raw value of the normalised `NSEvent.ModifierFlags`.
    let rawModifierFlags: UInt

    /// Default shortcut: ⌃⌥⌘S.
    ///
    /// The ⌃⌥⌘ combination is deliberately chosen because it is largely unused by macOS itself
    /// and by the major IDEs, which concentrate on ⌘, ⇧⌘, ⌥⌘ and ⌃⌘. ⌥Space is avoided because
    /// launchers such as Spotlight, Alfred and Raycast commonly occupy it.
    static let `default` = GlobalShortcut(keyCode: UInt16(kVK_ANSI_S), modifierFlags: [.control, .option, .command])

    /// Modifiers that are meaningful for a global shortcut. Everything else (caps lock, function,
    /// numeric pad, …) is discarded so that equality and registration stay predictable.
    static var relevantModifiers: NSEvent.ModifierFlags {
        [.command, .option, .control, .shift]
    }

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: rawModifierFlags)
    }

    /// Carbon modifier mask for `RegisterEventHotKey`.
    var carbonModifiers: UInt32 {
        var mask: UInt32 = 0

        if modifierFlags.contains(.command) {
            mask |= UInt32(cmdKey)
        }

        if modifierFlags.contains(.option) {
            mask |= UInt32(optionKey)
        }

        if modifierFlags.contains(.control) {
            mask |= UInt32(controlKey)
        }

        if modifierFlags.contains(.shift) {
            mask |= UInt32(shiftKey)
        }

        return mask
    }

    /// A shortcut needs at least one of ⌘, ⌥ or ⌃. Shift alone is not enough, because registering
    /// a bare or shifted key globally would swallow ordinary typing in every other application.
    var hasRequiredModifier: Bool {
        !modifierFlags.isDisjoint(with: [.command, .option, .control])
    }

    /// Modifier glyphs only, in the canonical macOS order, for example `⌃⌥⌘`.
    var modifierDisplayString: String {
        var result = ""

        if modifierFlags.contains(.control) {
            result += "⌃"
        }

        if modifierFlags.contains(.option) {
            result += "⌥"
        }

        if modifierFlags.contains(.shift) {
            result += "⇧"
        }

        if modifierFlags.contains(.command) {
            result += "⌘"
        }

        return result
    }

    /// Human readable form using the canonical macOS modifier order, for example `⌃⌥⌘S`.
    var displayString: String {
        modifierDisplayString + Self.keyName(for: keyCode)
    }

    init(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.rawModifierFlags = modifierFlags.intersection(Self.relevantModifiers).rawValue
    }

    /// Creates a shortcut from a recorded key event, or `nil` when the event carries no usable key.
    init?(event: NSEvent) {
        guard event.type == .keyDown else {
            return nil
        }

        self.init(keyCode: event.keyCode, modifierFlags: event.modifierFlags)
    }
}

extension GlobalShortcut {
    /// Keys that have no printable representation and therefore need an explicit glyph or name.
    private static let specialKeyNames: [UInt16: String] = [
        UInt16(kVK_Space): "Space",
        UInt16(kVK_Return): "↩",
        UInt16(kVK_ANSI_KeypadEnter): "⌤",
        UInt16(kVK_Tab): "⇥",
        UInt16(kVK_Delete): "⌫",
        UInt16(kVK_ForwardDelete): "⌦",
        UInt16(kVK_Escape): "⎋",
        UInt16(kVK_Home): "↖",
        UInt16(kVK_End): "↘",
        UInt16(kVK_PageUp): "⇞",
        UInt16(kVK_PageDown): "⇟",
        UInt16(kVK_LeftArrow): "←",
        UInt16(kVK_RightArrow): "→",
        UInt16(kVK_UpArrow): "↑",
        UInt16(kVK_DownArrow): "↓",
        UInt16(kVK_F1): "F1",
        UInt16(kVK_F2): "F2",
        UInt16(kVK_F3): "F3",
        UInt16(kVK_F4): "F4",
        UInt16(kVK_F5): "F5",
        UInt16(kVK_F6): "F6",
        UInt16(kVK_F7): "F7",
        UInt16(kVK_F8): "F8",
        UInt16(kVK_F9): "F9",
        UInt16(kVK_F10): "F10",
        UInt16(kVK_F11): "F11",
        UInt16(kVK_F12): "F12"
    ]

    /// Resolves the display name of a virtual key code.
    ///
    /// Special keys come from a fixed table; printable keys are translated through the active
    /// keyboard layout so that, for example, key code 6 reads `Y` on QWERTY and `Z` on QWERTZ.
    static func keyName(for keyCode: UInt16) -> String {
        if let specialName = specialKeyNames[keyCode] {
            return specialName
        }

        if let printableName = printableKeyName(for: keyCode) {
            return printableName
        }

        return "Key \(keyCode)"
    }

    private static func printableKeyName(for keyCode: UInt16) -> String? {
        guard let inputSource = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPointer = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }

        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var characterCount = 0
        var characters = [UniChar](repeating: 0, count: 4)

        let status = layoutData.withUnsafeBytes { buffer -> OSStatus in
            guard let keyboardLayout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return OSStatus(paramErr)
            }

            return UCKeyTranslate(keyboardLayout,
                                  keyCode,
                                  UInt16(kUCKeyActionDisplay),
                                  0,
                                  UInt32(LMGetKbdType()),
                                  UInt32(kUCKeyTranslateNoDeadKeysMask),
                                  &deadKeyState,
                                  characters.count,
                                  &characterCount,
                                  &characters)
        }

        guard status == noErr, characterCount > 0 else {
            return nil
        }

        let name = String(utf16CodeUnits: characters, count: characterCount).uppercased()

        return name.isEmpty ? nil : name
    }
}
