//
//  SnapshotContents.swift
//  SimulatorCore
//
//  Created by Nicolas Hiller on 21.10.26.
//

import Foundation

/// One part of a container a snapshot can be limited to.
public enum SnapshotContentKind: String, Codable, Sendable, Hashable, CaseIterable, Comparable {
    /// SQLite and Realm databases anywhere in the containers — see ``SnapshotDatabaseFormat``.
    case databases
    /// The `*.plist` domains directly inside each container's `Library/Preferences`.
    case userDefaults

    /// By raw value, which happens to read naturally: databases, then UserDefaults.
    public static func < (lhs: SnapshotContentKind, rhs: SnapshotContentKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .databases:
            "database"
        case .userDefaults:
            "UserDefaults"
        }
    }

    /// The wording of the panel's Save Snapshot to Folder rows, which a saved snapshot's label
    /// repeats.
    var labelName: String {
        switch self {
        case .databases:
            "Database"
        case .userDefaults:
            "UserDefaults"
        }
    }
}

/// What a snapshot holds: the whole container, or only some kinds of file in it.
///
/// Capture, restore and diff all take one, so the three agree about which files are in scope. If
/// they ever disagreed, a restore would delete files the snapshot never held.
///
/// Encoded as `"everything"` or as an array of ``SnapshotContentKind`` raw values, so a manifest says
/// what it holds in words a person reading the JSON understands.
public enum SnapshotContents: Sendable, Hashable {
    /// The whole container, which is what every snapshot was before contents existed.
    case everything
    /// Only these kinds of file. Empty only as the result of ``intersection(_:)``, where it means
    /// two snapshots have nothing in common to compare.
    case only(Set<SnapshotContentKind>)

    public static let databases = SnapshotContents.only([.databases])
    public static let userDefaults = SnapshotContents.only([.userDefaults])
    public static let databasesAndUserDefaults = SnapshotContents.only([.databases, .userDefaults])

    func includes(_ kind: SnapshotContentKind) -> Bool {
        switch self {
        case .everything:
            true
        case let .only(kinds):
            kinds.contains(kind)
        }
    }

    /// Whether this asks for nothing at all — two snapshots with no kind in common.
    var isEmpty: Bool {
        self == .only([])
    }

    /// What two snapshots both hold, which is all a diff between them can honestly compare.
    func intersection(_ other: SnapshotContents) -> SnapshotContents {
        switch (self, other) {
        case (.everything, _):
            other
        case (_, .everything):
            self
        case let (.only(lhs), .only(rhs)):
            .only(lhs.intersection(rhs))
        }
    }

    /// "database", "database and UserDefaults", "everything" — for a diff's header.
    var displayName: String {
        switch self {
        case .everything:
            "everything"
        case let .only(kinds) where kinds.isEmpty:
            "nothing"
        case let .only(kinds):
            kinds.sorted().map(\.displayName).joined(separator: " and ")
        }
    }

    /// Appended to a snapshot's label so the label says what the snapshot holds, in the words of
    /// the row it was saved from — "(Database and UserDefaults)". Empty for ``everything``, whose
    /// label stays what it always was.
    var labelSuffix: String {
        switch self {
        case .everything:
            ""
        case let .only(kinds):
            " (\(kinds.sorted().map(\.labelName).joined(separator: " and ")))"
        }
    }
}

extension SnapshotContents: Codable {
    private static let everythingValue = "everything"

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let value = try? container.decode(String.self) {
            guard value == Self.everythingValue else {
                throw DecodingError.dataCorruptedError(in: container,
                                                       debugDescription: "Unknown snapshot contents \(value)")
            }

            self = .everything

            return
        }

        self = try .only(Set(container.decode([SnapshotContentKind].self)))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .everything:
            try container.encode(Self.everythingValue)
        case let .only(kinds):
            try container.encode(kinds.sorted())
        }
    }
}

/// Which files of a container a capture, restore or diff works on.
///
/// The caches flag still applies to every set of contents: a database under `Library/Caches` is only
/// in scope when caches are included.
struct SnapshotScope: Sendable, Equatable {
    let contents: SnapshotContents
    let includeCaches: Bool

    static func everything(includeCaches: Bool) -> SnapshotScope {
        SnapshotScope(contents: .everything, includeCaches: includeCaches)
    }
}
