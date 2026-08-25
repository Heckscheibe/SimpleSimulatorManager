//
//  PasteboardWriting.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 25.08.26.
//

import AppKit
import Foundation

/// Writes text to the clipboard. Behind a protocol so copy actions can be tested without touching
/// the user's real pasteboard.
@MainActor
protocol PasteboardWriting: AnyObject {
    func write(_ string: String)
}

@MainActor
final class SystemPasteboard: PasteboardWriting {
    func write(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}
