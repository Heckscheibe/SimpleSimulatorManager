//
//  GlobalShortcutControllerTests.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 11.08.26.
//

import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import SimulatorManager

@Suite("GlobalShortcutController Tests")
@MainActor
struct GlobalShortcutControllerTests {
    // MARK: - Registration

    @Test("The stored shortcut is registered on start up")
    func storedShortcutIsRegistered() async {
        let context = TestContext()
        _ = context.makeController()

        await context.waitForPropagation()

        #expect(context.hotkeyService.registeredShortcut == .default)
    }

    @Test("Changing the shortcut re-registers the new combination")
    func changingShortcutReRegisters() async {
        let context = TestContext()
        _ = context.makeController()

        await context.waitForPropagation()

        let replacement = GlobalShortcut(keyCode: UInt16(kVK_ANSI_K), modifierFlags: [.command, .option])
        context.settings.updateGlobalShortcut(replacement)

        await context.waitForPropagation()

        #expect(context.hotkeyService.registeredShortcut == replacement)
        #expect(context.hotkeyService.registeredShortcuts.count == 2)
    }

    @Test("Clearing the shortcut unregisters it")
    func clearingShortcutUnregisters() async {
        let context = TestContext()
        _ = context.makeController()

        await context.waitForPropagation()

        context.settings.updateGlobalShortcut(nil)

        await context.waitForPropagation()

        #expect(context.hotkeyService.unregisterCallCount == 1)
    }

    @Test("Setting the same shortcut again does not re-register")
    func identicalShortcutDoesNotReRegister() async {
        let context = TestContext()
        _ = context.makeController()

        await context.waitForPropagation()

        context.settings.updateGlobalShortcut(.default)

        await context.waitForPropagation()

        #expect(context.hotkeyService.registeredShortcuts.count == 1)
    }

    // MARK: - Triggering

    @Test("Pressing the shortcut opens the menu")
    func triggerOpensMenu() async {
        let context = TestContext()
        let controller = context.makeController()

        await context.waitForPropagation()

        context.hotkeyService.simulateTrigger()

        #expect(context.menuPresenter.openMenuCallCount == 1)
        #expect(controller.registrationErrorMessage == nil)
    }

    @Test("An unreachable status item surfaces an error instead of failing silently")
    func unreachableMenuSurfacesError() async {
        let context = TestContext()
        context.menuPresenter.openMenuResult = false
        let controller = context.makeController()

        await context.waitForPropagation()

        context.hotkeyService.simulateTrigger()

        #expect(controller.registrationErrorMessage != nil)
    }

    // MARK: - Error Handling

    @Test("A conflicting shortcut surfaces the registration error")
    func conflictingShortcutSurfacesError() async {
        let context = TestContext()
        context.hotkeyService.errorToThrow = .alreadyInUse
        let controller = context.makeController()

        await context.waitForPropagation()

        #expect(controller.registrationErrorMessage == GlobalHotkeyError.alreadyInUse.errorDescription)
    }

    @Test("A successful registration clears a previous error")
    func successfulRegistrationClearsError() async {
        let context = TestContext()
        context.hotkeyService.errorToThrow = .alreadyInUse
        let controller = context.makeController()

        await context.waitForPropagation()

        #expect(controller.registrationErrorMessage != nil)

        context.hotkeyService.errorToThrow = nil
        context.settings.updateGlobalShortcut(GlobalShortcut(keyCode: UInt16(kVK_ANSI_K),
                                                             modifierFlags: [.command, .option]))

        await context.waitForPropagation()

        #expect(controller.registrationErrorMessage == nil)
    }
}

@MainActor
private class TestContext {
    let settings: Settings
    let hotkeyService = MockGlobalHotkeyService()
    let menuPresenter = MockMenuBarMenuPresenter()

    /// Retained here: the controller's Combine subscription only lives as long as the controller,
    /// and shortcut changes are delivered asynchronously on the main queue.
    private var controller: GlobalShortcutController?

    private let suiteName = "SimulatorManagerTests.\(UUID().uuidString)"

    init() {
        settings = Settings(userDefaults: UserDefaults(suiteName: suiteName))
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    func makeController() -> GlobalShortcutController {
        let controller = GlobalShortcutController(settings: settings,
                                                  hotkeyService: hotkeyService,
                                                  menuPresenter: menuPresenter)
        self.controller = controller

        return controller
    }

    /// The controller receives shortcut changes on the main queue, so assertions have to wait for
    /// that hop to complete.
    func waitForPropagation() async {
        try? await Task.sleep(for: .milliseconds(50))
    }
}
