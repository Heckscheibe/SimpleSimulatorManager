//
//  SnapshotExportNaming.swift
//  SimulatorCore
//
//  Created by Nicolas Hiller on 20.10.26.
//

import Foundation

/// Names a snapshot saved to a folder the user picked: `DEVICE_OSVERSION_APPNAME_DATE`, for
/// example `iPhone-16-Pro_iOS-18.2_My-App_2026-10-20_14-30-05`.
///
/// The internal store names snapshots by UUID, which is fine for a directory only this app reads.
/// A saved snapshot lands in Downloads, next to everything else the user has, and has to say what
/// it is at a glance — and sort by date within one app on one device.
///
/// `_` separates the fields and never appears inside the device, OS or app name, so the first three
/// components of a split are those names and the rest is the date (which has a `_` of its own).
package enum SnapshotExportNaming {
    /// In bytes, because the 255 limit on a file name is in bytes, and a name of 40 characters can
    /// be 160 of them. Three fields at this cap plus the date and a collision suffix stay inside it,
    /// and it is still far longer than any real device or app name written in ASCII.
    static let maximumFieldByteCount = 64
    static let fieldSeparator = "_"
    static let emptyFieldPlaceholder = "unknown"

    /// - Parameters:
    ///   - date: When the snapshot was captured.
    ///   - timeZone: Injectable so tests do not depend on the machine's zone. The name is for the
    ///     person reading Finder, so it uses their local time.
    package static func folderName(
        deviceName: String,
        osVersion: String,
        appName: String,
        date: Date,
        timeZone: TimeZone = .current
    ) -> String {
        [
            sanitizedField(deviceName),
            sanitizedField(osVersion),
            sanitizedField(appName),
            formattedDate(date, timeZone: timeZone)
        ].joined(separator: fieldSeparator)
    }

    /// The first of `name`, `name 2`, `name 3`, … that does not exist in `directoryURL`.
    ///
    /// An existing folder is never overwritten or merged into: two snapshots taken in the same
    /// second would otherwise interleave their containers into one folder that is neither.
    static func uniqueDestinationURL(
        in directoryURL: URL,
        folderName: String,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL {
        var candidate = directoryURL.appendingPathComponent(folderName, isDirectory: true)
        var suffix = 2

        while fileExists(candidate) {
            candidate = directoryURL.appendingPathComponent("\(folderName) \(suffix)", isDirectory: true)
            suffix += 1
        }

        return candidate
    }
}

// MARK: - Fields

extension SnapshotExportNaming {
    /// Whitespace runs become `-`, and so do `_` (reserved as the separator), `/` and `:` (path
    /// separators to the filesystem and to Finder respectively) and control characters. Runs of `-`
    /// collapse, and leading or trailing `-` and `.` go — a leading `.` would hide the folder.
    static func sanitizedField(_ value: String) -> String {
        var result = ""
        var lastWasDash = false

        for character in value {
            let isReplaced = character.isWhitespace
                || character == "_"
                || character == "/"
                || character == ":"
                || character == "-"
                // Control characters proper (Cc), not `CharacterSet.controlCharacters`: that also
                // holds format characters such as the zero-width joiner, and would break every
                // multi-person or skin-tone emoji into pieces.
                || character.unicodeScalars.contains { $0.properties.generalCategory == .control }

            if isReplaced {
                if !lastWasDash {
                    result.append("-")
                }
                lastWasDash = true
            } else {
                result.append(character)
                lastWasDash = false
            }
        }

        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        let capped = cappedToByteCount(trimmed).trimmingCharacters(in: CharacterSet(charactersIn: "-."))

        return capped.isEmpty ? emptyFieldPlaceholder : capped
    }

    /// Drops whole `Character`s from the end, so an emoji or a composed accent is kept or dropped
    /// as a unit and never split into a broken sequence. Measured decomposed: HFS+ and some file
    /// servers store names in that form, where `ü` costs three bytes instead of two.
    static func cappedToByteCount(_ value: String) -> String {
        var capped = value

        while capped.decomposedStringWithCanonicalMapping.utf8.count > maximumFieldByteCount {
            capped.removeLast()
        }

        return capped
    }

    /// Sortable, and free of `:` — Finder shows a `:` in a name as `/`, which reads as a path.
    static func formattedDate(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"

        return formatter.string(from: date)
    }
}
