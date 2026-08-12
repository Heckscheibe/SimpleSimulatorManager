//
//  GlobalHotkeyService.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 11.08.26.
//

import AppKit
import Carbon.HIToolbox
import Foundation
import os

enum GlobalHotkeyError: LocalizedError, Equatable {
    /// The shortcut carries no modifier, which would swallow ordinary typing system wide.
    case missingModifier

    /// Another application already owns this combination.
    case alreadyInUse

    /// Carbon refused the registration for any other reason.
    case registrationFailed(OSStatus)

    /// The Carbon event handler could not be installed.
    case eventHandlerUnavailable

    var errorDescription: String? {
        switch self {
        case .missingModifier:
            return "A shortcut needs at least one of ⌘, ⌥ or ⌃."
        case .alreadyInUse:
            return "This shortcut is already used by another application. Pick a different combination."
        case let .registrationFailed(status):
            return "The shortcut could not be registered (error \(status))."
        case .eventHandlerUnavailable:
            return "The shortcut could not be registered because the keyboard event handler is unavailable."
        }
    }
}

@MainActor
protocol GlobalHotkeyServing: AnyObject {
    /// Registers `shortcut` system wide, replacing any previously registered one.
    /// - Throws: ``GlobalHotkeyError`` when the shortcut is invalid or cannot be claimed.
    func register(_ shortcut: GlobalShortcut, handler: @escaping @MainActor () -> Void) throws

    /// Releases the currently registered shortcut, if any.
    func unregister()
}

/// Registers a system wide hotkey through the Carbon Event Manager.
///
/// Carbon is used deliberately: `NSEvent.addGlobalMonitorForEvents` would require the user to
/// grant Accessibility permission, which is a disproportionate cost for a menu bar utility, and
/// `RegisterEventHotKey` remains the supported way to claim a hotkey without extra entitlements.
@MainActor
final class GlobalHotkeyService: GlobalHotkeyServing {
    /// Four character signature identifying hotkeys owned by this app ('SIMM').
    private static let hotKeySignature = OSType(0x5349_4D4D)
    private static let hotKeyIdentifier: UInt32 = 1

    /// Carbon state lives in a separate, non-isolated object so that it can be released from
    /// `deinit`: a `deinit` on a main actor isolated class is itself nonisolated and may not touch
    /// isolated stored properties.
    private let registration = CarbonHotkeyRegistration()

    func register(_ shortcut: GlobalShortcut, handler: @escaping @MainActor () -> Void) throws {
        guard shortcut.hasRequiredModifier else {
            throw GlobalHotkeyError.missingModifier
        }

        unregister()

        try installEventHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: Self.hotKeyIdentifier)
        var registeredRef: EventHotKeyRef?

        let status = RegisterEventHotKey(UInt32(shortcut.keyCode),
                                         shortcut.carbonModifiers,
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &registeredRef)

        guard status == noErr, let registeredRef else {
            os_log("Global hotkey registration failed for %{public}@ with status %{public}d", shortcut.displayString, status)

            throw status == OSStatus(eventHotKeyExistsErr)
                ? GlobalHotkeyError.alreadyInUse
                : GlobalHotkeyError.registrationFailed(status)
        }

        registration.hotKeyRef = registeredRef
        registration.handler = handler
        registration.signature = Self.hotKeySignature
        registration.identifier = Self.hotKeyIdentifier

        os_log("Global hotkey registered: %{public}@", shortcut.displayString)
    }

    func unregister() {
        guard let hotKeyRef = registration.hotKeyRef else {
            return
        }

        UnregisterEventHotKey(hotKeyRef)
        registration.hotKeyRef = nil
        registration.handler = nil

        os_log("Global hotkey unregistered")
    }
}

/// Owns the raw Carbon handles and the trigger callback.
///
/// Marked `@unchecked Sendable` because its mutable state is only ever touched from the main
/// actor (by ``GlobalHotkeyService``) or from the Carbon callback, which is delivered on the main
/// thread. It is also the context pointer handed to Carbon, so the installed handler can never
/// outlive the object it calls back into.
private final class CarbonHotkeyRegistration: @unchecked Sendable {
    var hotKeyRef: EventHotKeyRef?
    var eventHandlerRef: EventHandlerRef?
    var handler: (@MainActor () -> Void)?
    var signature = OSType(0)
    var identifier: UInt32 = 0

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func handleHotKeyPressed(identifier hotKeyIdentifier: EventHotKeyID) {
        guard hotKeyIdentifier.signature == signature, hotKeyIdentifier.id == identifier else {
            return
        }

        MainActor.assumeIsolated {
            handler?()
        }
    }
}

private extension GlobalHotkeyService {
    /// Installs the Carbon event handler once and keeps it for the lifetime of the service.
    ///
    /// The handler is shared across registrations; only the hotkey itself is re-registered when
    /// the user changes the shortcut.
    func installEventHandlerIfNeeded() throws {
        guard registration.eventHandlerRef == nil else {
            return
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: OSType(kEventHotKeyPressed))
        var installedRef: EventHandlerRef?

        // Carbon callbacks are plain C function pointers and cannot capture context, so the
        // registration is handed through as unmanaged user data. It is passed unretained because
        // the registration removes the handler in its own `deinit`, so the callback can never
        // reference a deallocated object.
        let context = Unmanaged.passUnretained(registration).toOpaque()

        let status = InstallEventHandler(GetApplicationEventTarget(),
                                         globalHotkeyEventHandler,
                                         1,
                                         &eventType,
                                         context,
                                         &installedRef)

        guard status == noErr, let installedRef else {
            os_log("Global hotkey event handler could not be installed, status %{public}d", status)

            throw GlobalHotkeyError.eventHandlerUnavailable
        }

        registration.eventHandlerRef = installedRef
    }
}

/// Carbon event callback. Runs on the main thread as part of the application event loop.
private func globalHotkeyEventHandler(
    callRef: EventHandlerCallRef?,
    event: EventRef?,
    context: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let context else {
        return OSStatus(eventNotHandledErr)
    }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event,
                                   EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID),
                                   nil,
                                   MemoryLayout<EventHotKeyID>.size,
                                   nil,
                                   &hotKeyID)

    guard status == noErr else {
        return status
    }

    let registration = Unmanaged<CarbonHotkeyRegistration>.fromOpaque(context).takeUnretainedValue()
    registration.handleHotKeyPressed(identifier: hotKeyID)

    return noErr
}
