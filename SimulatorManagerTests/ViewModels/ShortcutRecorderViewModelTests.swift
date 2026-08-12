//
//  ShortcutRecorderViewModelTests.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 11.08.26.
//

import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import SimulatorManager

@Suite("ShortcutRecorderViewModel Tests")
@MainActor
struct ShortcutRecorderViewModelTests {
    // MARK: - Recording State

    @Test("Starting recording clears any previous validation message")
    func startRecordingResetsState() throws {
        let context = TestContext()
        let viewModel = context.makeViewModel()

        viewModel.startRecording()
        try viewModel.handleKeyDown(context.keyEvent(keyCode: UInt16(kVK_ANSI_S), modifiers: []))

        #expect(viewModel.validationMessage != nil)

        viewModel.startRecording()

        #expect(viewModel.validationMessage == nil)
        #expect(viewModel.isRecording)
    }

    @Test("Key presses are ignored while not recording")
    func keyPressesIgnoredWhenNotRecording() throws {
        let context = TestContext()
        let viewModel = context.makeViewModel()

        try viewModel.handleKeyDown(context.keyEvent(keyCode: UInt16(kVK_ANSI_K), modifiers: [.command, .option]))

        #expect(viewModel.shortcut == .default)
    }

    // MARK: - Capture

    @Test("A valid combination is captured and stored")
    func validCombinationIsStored() throws {
        let context = TestContext()
        let viewModel = context.makeViewModel()

        viewModel.startRecording()
        try viewModel.handleKeyDown(context.keyEvent(keyCode: UInt16(kVK_ANSI_K), modifiers: [.command, .option]))

        #expect(viewModel.shortcut == GlobalShortcut(keyCode: UInt16(kVK_ANSI_K), modifierFlags: [.command, .option]))
        #expect(!viewModel.isRecording)
        #expect(viewModel.validationMessage == nil)
    }

    @Test("A combination without a required modifier is rejected and recording continues")
    func combinationWithoutModifierIsRejected() throws {
        let context = TestContext()
        let viewModel = context.makeViewModel()

        viewModel.startRecording()
        try viewModel.handleKeyDown(context.keyEvent(keyCode: UInt16(kVK_ANSI_K), modifiers: [.shift]))

        #expect(viewModel.shortcut == .default, "The stored shortcut must not change on an invalid capture")
        #expect(viewModel.isRecording, "Recording should continue so the user can try again")
        #expect(viewModel.validationMessage == GlobalHotkeyError.missingModifier.errorDescription)
    }

    // MARK: - Escape and Delete

    @Test("Escape aborts recording and keeps the previous shortcut")
    func escapeCancelsRecording() throws {
        let context = TestContext()
        let viewModel = context.makeViewModel()

        viewModel.startRecording()
        try viewModel.handleKeyDown(context.keyEvent(keyCode: UInt16(kVK_Escape), modifiers: []))

        #expect(!viewModel.isRecording)
        #expect(viewModel.shortcut == .default)
    }

    @Test("Delete clears the shortcut")
    func deleteClearsShortcut() throws {
        let context = TestContext()
        let viewModel = context.makeViewModel()

        viewModel.startRecording()
        try viewModel.handleKeyDown(context.keyEvent(keyCode: UInt16(kVK_Delete), modifiers: []))

        #expect(viewModel.shortcut == nil)
        #expect(!viewModel.isRecording)
    }

    @Test("Escape and delete can still be recorded when combined with modifiers")
    func modifiedEscapeAndDeleteAreRecordable() throws {
        let context = TestContext()
        let viewModel = context.makeViewModel()

        viewModel.startRecording()
        try viewModel.handleKeyDown(context.keyEvent(keyCode: UInt16(kVK_Delete),
                                                     modifiers: [.control, .option, .command]))

        #expect(viewModel.shortcut == GlobalShortcut(keyCode: UInt16(kVK_Delete),
                                                     modifierFlags: [.control, .option, .command]))
    }

    // MARK: - Clear and Reset

    @Test("Clearing removes the shortcut and disables the clear action")
    func clearRemovesShortcut() {
        let context = TestContext()
        let viewModel = context.makeViewModel()

        #expect(viewModel.canClear)

        viewModel.clearShortcut()

        #expect(viewModel.shortcut == nil)
        #expect(!viewModel.canClear)
    }

    @Test("Resetting restores the default shortcut")
    func resetRestoresDefault() {
        let context = TestContext()
        let viewModel = context.makeViewModel()

        viewModel.clearShortcut()
        viewModel.resetToDefault()

        #expect(viewModel.shortcut == .default)
    }

    // MARK: - Display

    @Test("The control shows the stored shortcut when idle")
    func displayShowsStoredShortcut() {
        let context = TestContext()
        let viewModel = context.makeViewModel()

        #expect(viewModel.displayText == GlobalShortcut.default.displayString)
    }

    @Test("The control shows a placeholder when no shortcut is set")
    func displayShowsPlaceholderWhenCleared() {
        let context = TestContext()
        let viewModel = context.makeViewModel()

        viewModel.clearShortcut()

        #expect(viewModel.displayText == "None")
    }

    @Test("The control shows live modifiers while recording")
    func displayShowsLiveModifiers() {
        let context = TestContext()
        let viewModel = context.makeViewModel()

        viewModel.startRecording()

        #expect(viewModel.displayText == "Type a shortcut…")

        viewModel.updatePendingModifiers([.control, .command])

        #expect(viewModel.displayText == "⌃⌘")
    }

    @Test("Live modifiers are ignored while not recording")
    func liveModifiersIgnoredWhenNotRecording() {
        let context = TestContext()
        let viewModel = context.makeViewModel()

        viewModel.updatePendingModifiers([.control, .command])

        #expect(viewModel.pendingModifiers.isEmpty)
    }
}

@MainActor
private class TestContext {
    let settings: Settings

    private let suiteName = "SimulatorManagerTests.\(UUID().uuidString)"

    init() {
        settings = Settings(userDefaults: UserDefaults(suiteName: suiteName))
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    func makeViewModel() -> ShortcutRecorderViewModel {
        ShortcutRecorderViewModel(settings: settings)
    }

    func keyEvent(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown,
                                      location: .zero,
                                      modifierFlags: modifiers,
                                      timestamp: 0,
                                      windowNumber: 0,
                                      context: nil,
                                      characters: "",
                                      charactersIgnoringModifiers: "",
                                      isARepeat: false,
                                      keyCode: keyCode))
    }
}
