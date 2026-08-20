//
//  ShortcutRecorderViewModel.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 11.08.26.
//

import AppKit
import Carbon.HIToolbox
import Foundation
import Observation

/// Drives the shortcut recorder control: capturing a key combination, validating it and writing it
/// back to ``Settings``.
@MainActor
@Observable
class ShortcutRecorderViewModel {
    @ObservationIgnored private let settings: Settings

    /// Whether the control is currently listening for a key combination.
    private(set) var isRecording = false

    /// Modifiers held down while recording, so the control can show live feedback.
    private(set) var pendingModifiers = NSEvent.ModifierFlags()

    /// Explains why the last captured combination was rejected.
    private(set) var validationMessage: String?

    init(settings: Settings) {
        self.settings = settings
    }

    var shortcut: GlobalShortcut? {
        settings.globalShortcut
    }

    /// What the control shows: live modifiers while recording, otherwise the stored shortcut.
    var displayText: String {
        guard isRecording else {
            return settings.globalShortcut?.displayString ?? "None"
        }

        let modifierText = GlobalShortcut(keyCode: 0, modifierFlags: pendingModifiers).modifierDisplayString

        return modifierText.isEmpty ? "Type a shortcut…" : modifierText
    }

    var canClear: Bool {
        settings.globalShortcut != nil
    }

    func startRecording() {
        isRecording = true
        pendingModifiers = NSEvent.ModifierFlags()
        validationMessage = nil
    }

    func cancelRecording() {
        isRecording = false
        pendingModifiers = NSEvent.ModifierFlags()
        validationMessage = nil
    }

    func clearShortcut() {
        cancelRecording()
        settings.updateGlobalShortcut(nil)
    }

    func resetToDefault() {
        cancelRecording()
        settings.updateGlobalShortcut(.default)
    }

    func updatePendingModifiers(_ modifiers: NSEvent.ModifierFlags) {
        guard isRecording else {
            return
        }

        pendingModifiers = modifiers.intersection(GlobalShortcut.relevantModifiers)
    }

    /// Handles a key press while recording.
    func handleKeyDown(_ event: NSEvent) {
        guard isRecording else {
            return
        }

        let modifiers = event.modifierFlags.intersection(GlobalShortcut.relevantModifiers)

        // Escape abandons recording and keeps the previous shortcut; delete clears it. Both only
        // when pressed on their own, so ⌃⌥⌘⌫ can still be recorded as a shortcut.
        if event.keyCode == UInt16(kVK_Escape), modifiers.isEmpty {
            cancelRecording()

            return
        }

        if event.keyCode == UInt16(kVK_Delete), modifiers.isEmpty {
            clearShortcut()

            return
        }

        guard let shortcut = GlobalShortcut(event: event) else {
            return
        }
        guard shortcut.hasRequiredModifier else {
            validationMessage = GlobalHotkeyError.missingModifier.errorDescription

            return
        }

        settings.updateGlobalShortcut(shortcut)
        isRecording = false
        pendingModifiers = NSEvent.ModifierFlags()
        validationMessage = nil
    }
}
