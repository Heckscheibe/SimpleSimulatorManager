//
//  ShortcutRecorderView.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 11.08.26.
//

import AppKit
import SwiftUI

/// A control that records a global keyboard shortcut.
///
/// Clicking it starts recording; the next key combination is captured and stored. Escape aborts,
/// delete clears the shortcut.
struct ShortcutRecorderView: View {
    let viewModel: ShortcutRecorderViewModel

    var body: some View {
        HStack(spacing: 8) {
            Button {
                if viewModel.isRecording {
                    viewModel.cancelRecording()
                } else {
                    viewModel.startRecording()
                }
            } label: {
                Text(viewModel.displayText)
                    .frame(minWidth: 120)
                    .monospaced()
            }
            .background {
                // The capture view is only in the hierarchy while recording, so it cannot steal
                // key events from the rest of the settings window.
                if viewModel.isRecording {
                    KeyCaptureView(onKeyDown: viewModel.handleKeyDown,
                                   onModifiersChanged: viewModel.updatePendingModifiers)
                        .frame(width: 0, height: 0)
                }
            }

            Button("Clear") {
                viewModel.clearShortcut()
            }
            .disabled(!viewModel.canClear)

            Button("Reset") {
                viewModel.resetToDefault()
            }
        }
    }
}

/// Bridges AppKit key events into SwiftUI while the recorder is active.
private struct KeyCaptureView: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Void
    let onModifiersChanged: (NSEvent.ModifierFlags) -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onKeyDown = onKeyDown
        view.onModifiersChanged = onModifiersChanged

        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.onKeyDown = onKeyDown
        nsView.onModifiersChanged = onModifiersChanged

        // Claim first responder as soon as the view is in a window, otherwise the key events go
        // to the settings window instead of the recorder.
        DispatchQueue.main.async {
            guard let window = nsView.window, window.firstResponder !== nsView else {
                return
            }

            window.makeFirstResponder(nsView)
        }
    }
}

private class KeyCaptureNSView: NSView {
    var onKeyDown: ((NSEvent) -> Void)?
    var onModifiersChanged: ((NSEvent.ModifierFlags) -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        onKeyDown?(event)
    }

    override func flagsChanged(with event: NSEvent) {
        onModifiersChanged?(event.modifierFlags)
    }

    /// Combinations containing ⌘ are delivered as key equivalents and would otherwise be consumed
    /// by the main menu before reaching `keyDown`.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else {
            return false
        }

        onKeyDown?(event)

        return true
    }
}
