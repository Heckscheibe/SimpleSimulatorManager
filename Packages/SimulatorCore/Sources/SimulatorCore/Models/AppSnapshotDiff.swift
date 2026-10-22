//
//  AppSnapshotDiff.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 05.09.26.
//

import Foundation

/// A file that differs between two container states.
public struct SnapshotFileChange: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case added
        case removed
        case modified
    }

    public let kind: Kind
    /// Path relative to the container root, so the same file compares equal across devices.
    public let relativePath: String
    public let oldByteSize: Int64?
    public let newByteSize: Int64?
}

/// A single defaults key that differs.
///
/// Reported per key rather than as one modified plist: "`Library/Preferences/com.acme.app.plist`
/// changed" answers nothing, and reading the plist by hand to find out which key moved is exactly
/// the trip to Terminal this feature exists to remove.
public struct SnapshotDefaultsChange: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case added
        case removed
        case changed
    }

    public let kind: Kind
    public let domain: String
    public let key: String
    public let oldValue: String?
    public let newValue: String?
}

/// The differences found in one container.
public struct SnapshotContainerDiff: Sendable, Equatable {
    public let kind: SnapshotContainerKind
    public let fileChanges: [SnapshotFileChange]
    public let defaultsChanges: [SnapshotDefaultsChange]

    public var hasChanges: Bool {
        !fileChanges.isEmpty || !defaultsChanges.isEmpty
    }
}

/// The result of comparing two container states, container by container.
public struct AppSnapshotDiff: Sendable, Equatable {
    /// What was compared, for the exported header — "Snapshot A" against "the live container".
    public let oldDescription: String
    public let newDescription: String
    /// What both sides hold, and so what was compared. Anything else was left out on purpose — a
    /// databases-only snapshot says nothing about the documents beside them.
    public let comparedContents: SnapshotContents
    public let containerDiffs: [SnapshotContainerDiff]

    public var hasChanges: Bool {
        containerDiffs.contains { $0.hasChanges }
    }
}

extension AppSnapshotDiff {
    /// The diff as plain text, which is what gets exported.
    public var renderedText: String {
        var lines = ["\(oldDescription) → \(newDescription)"]

        if comparedContents != .everything {
            lines.append("Compared: \(comparedContents.displayName)")
        }

        lines.append("")

        guard hasChanges else {
            lines.append("No differences.")

            return lines.joined(separator: "\n")
        }

        for containerDiff in containerDiffs where containerDiff.hasChanges {
            lines.append(containerDiff.kind.displayName)
            lines.append(String(repeating: "-", count: containerDiff.kind.displayName.count))

            for change in containerDiff.fileChanges {
                lines.append("  \(Self.marker(for: change.kind)) \(change.relativePath)\(Self.sizeSuffix(for: change))")
            }

            if !containerDiff.defaultsChanges.isEmpty {
                lines.append("")
                lines.append("  UserDefaults")

                for change in containerDiff.defaultsChanges {
                    lines.append("    \(Self.marker(for: change.kind)) \(change.domain) / \(change.key)\(Self.valueSuffix(for: change))")
                }
            }

            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private static func marker(for kind: SnapshotFileChange.Kind) -> String {
        switch kind {
        case .added:
            "+"
        case .removed:
            "-"
        case .modified:
            "~"
        }
    }

    private static func marker(for kind: SnapshotDefaultsChange.Kind) -> String {
        switch kind {
        case .added:
            "+"
        case .removed:
            "-"
        case .changed:
            "~"
        }
    }

    private static func sizeSuffix(for change: SnapshotFileChange) -> String {
        switch change.kind {
        case .added:
            " (\(formatted(change.newByteSize)))"
        case .removed:
            " (\(formatted(change.oldByteSize)))"
        case .modified:
            " (\(formatted(change.oldByteSize)) → \(formatted(change.newByteSize)))"
        }
    }

    private static func valueSuffix(for change: SnapshotDefaultsChange) -> String {
        switch change.kind {
        case .added:
            ": \(change.newValue ?? "-")"
        case .removed:
            ": \(change.oldValue ?? "-")"
        case .changed:
            ": \(change.oldValue ?? "-") → \(change.newValue ?? "-")"
        }
    }

    private static func formatted(_ byteCount: Int64?) -> String {
        guard let byteCount else {
            return "unknown size"
        }

        return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}
