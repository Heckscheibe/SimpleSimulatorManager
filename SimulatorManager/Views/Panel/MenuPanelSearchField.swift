//
//  MenuPanelSearchField.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 04.09.26.
//

import AppKit
import SwiftUI

/// The panel's search field.
///
/// An `NSSearchField` rather than a SwiftUI `TextField`, because the field has to hold focus — the
/// user must be able to type the moment the panel opens — while the arrow keys and <kbd>↩</kbd>
/// still drive the list behind it. AppKit's field editor routes exactly those keys through
/// `doCommandBy`, which makes claiming them precise instead of a guess about which view sees a key
/// press first.
struct MenuPanelSearchField: NSViewRepresentable {
    /// A key the list wants, rather than the text field.
    enum Command: Equatable {
        case moveUp
        case moveDown
        case moveLeft
        case moveRight
        case activate(MenuPanelActionKind)
        case cancel
    }

    @Binding var query: String
    let placeholder: String
    /// Returns whether the list consumed the command. When it does not, the field keeps its normal
    /// behaviour — which is what lets ←/→ move the caret once there is something to edit.
    let performCommand: (Command) -> Bool

    func makeNSView(context: Context) -> MenuPanelSearchTextField {
        let field = MenuPanelSearchTextField()
        field.delegate = context.coordinator
        field.placeholderString = placeholder
        field.sendsWholeSearchString = false
        field.sendsSearchStringImmediately = true
        field.focusRingType = .none
        field.bezelStyle = .roundedBezel
        field.onCommandReturn = { performCommand(.activate(.secondary(index: 0))) }

        return field
    }

    func updateNSView(_ nsView: MenuPanelSearchTextField, context: Context) {
        context.coordinator.performCommand = performCommand
        nsView.onCommandReturn = { performCommand(.activate(.secondary(index: 0))) }

        if nsView.stringValue != query {
            nsView.stringValue = query
        }

        claimFocus(for: nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(query: $query, performCommand: performCommand)
    }
}

private extension MenuPanelSearchField {
    /// The panel has to be typeable the moment it opens, and nothing else in it takes focus, so the
    /// field claims it whenever the panel is the key window.
    func claimFocus(for field: NSSearchField) {
        DispatchQueue.main.async {
            guard let window = field.window, window.isKeyWindow else {
                return
            }
            guard window.firstResponder !== field.currentEditor() else {
                return
            }

            window.makeFirstResponder(field)
        }
    }
}

// MARK: - Coordinator

extension MenuPanelSearchField {
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var performCommand: (Command) -> Bool

        private let query: Binding<String>

        init(query: Binding<String>, performCommand: @escaping (Command) -> Bool) {
            self.query = query
            self.performCommand = performCommand
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else {
                return
            }

            query.wrappedValue = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard let command = Self.command(for: selector) else {
                return false
            }

            // ←/→ are only the list's while there is nothing to edit. Once the user has typed, the
            // caret needs them more than the drill-down does.
            if command == .moveLeft || command == .moveRight, !control.stringValue.isEmpty {
                return false
            }

            return performCommand(command)
        }

        private static func command(for selector: Selector) -> Command? {
            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                return .moveUp
            case #selector(NSResponder.moveDown(_:)):
                return .moveDown
            case #selector(NSResponder.moveLeft(_:)):
                return .moveLeft
            case #selector(NSResponder.moveRight(_:)):
                return .moveRight
            case #selector(NSResponder.insertNewline(_:)):
                return .activate(.primary)
            case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                // What the field editor sends for ⌥↩.
                return .activate(.secondary(index: 1))
            case #selector(NSResponder.cancelOperation(_:)):
                return .cancel
            default:
                return nil
            }
        }
    }
}

// MARK: - Field

/// Claims ⌘↩, which never reaches `doCommandBy` because AppKit offers a command-modified key to the
/// responder chain as a key equivalent first.
final class MenuPanelSearchTextField: NSSearchField {
    var onCommandReturn: (() -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let isReturn = event.keyCode == Self.returnKeyCode || event.keyCode == Self.enterKeyCode
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if isReturn, modifiers == .command, onCommandReturn?() == true {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    private static let returnKeyCode: UInt16 = 36
    private static let enterKeyCode: UInt16 = 76
}
