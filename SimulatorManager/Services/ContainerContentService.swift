//
//  ContainerContentService.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 25.08.26.
//

import Foundation
import os

/// Puts container *content* on the clipboard, as opposed to ``FolderOpening``, which reveals
/// containers in Finder.
@MainActor
protocol ContainerContentCopying: AnyObject {
    /// Copies `url` in a form that resolves as-is when pasted into a terminal.
    func copyPath(of url: URL)

    /// Copies the preferences at `url` as JSON, or reports why it could not.
    /// - Parameter subject: What the preferences belong to, used in the failure message.
    func copyUserDefaultsJSON(fromPreferencesDirectoryAt url: URL, preferredPlistName: String, subject: String)
}

@MainActor
final class ContainerContentService: ContainerContentCopying {
    private let pasteboard: PasteboardWriting
    private let exporter: UserDefaultsExporting
    private let errorReporter: UserFacingErrorReporting

    init(
        pasteboard: PasteboardWriting = SystemPasteboard(),
        exporter: UserDefaultsExporting = UserDefaultsExportService(),
        errorReporter: UserFacingErrorReporting = AlertErrorReporter()
    ) {
        self.pasteboard = pasteboard
        self.exporter = exporter
        self.errorReporter = errorReporter
    }

    func copyPath(of url: URL) {
        pasteboard.write(url.path.shellEscaped)
    }

    func copyUserDefaultsJSON(fromPreferencesDirectoryAt url: URL, preferredPlistName: String, subject: String) {
        do {
            let json = try exporter.exportJSON(fromPreferencesDirectoryAt: url, preferredPlistName: preferredPlistName)

            pasteboard.write(json)
        } catch {
            // The clipboard keeps whatever it held: an empty or partial export would be worse than
            // no export at all.
            os_log("Failed to export UserDefaults for \(subject) at \(url) due to error: \(error)")

            errorReporter.report(title: "Could not copy UserDefaults for \(subject)",
                                 message: error.localizedDescription)
        }
    }
}
