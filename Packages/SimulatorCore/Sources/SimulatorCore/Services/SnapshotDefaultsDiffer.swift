//
//  SnapshotDefaultsDiffer.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 05.09.26.
//

import Foundation
import os

/// Compares two versions of a defaults plist key by key.
///
/// A container's `Library/Preferences` is where most of what an app "remembers" actually lives, and
/// reporting it as one modified file says nothing at all — the plist is a single blob that changes
/// whenever anything in it does. This is the only file type the diff opens rather than hashing.
enum SnapshotDefaultsDiffer {
    /// Whether `relativePath` is a defaults plist inside a container, and so belongs to this
    /// comparison rather than to the file-level one.
    static func isDefaultsPlist(_ relativePath: String) -> Bool {
        let path = relativePath as NSString

        // Only the domain files sit directly in `Library/Preferences`. Anything nested deeper was
        // put there by something other than `UserDefaults` and is left to the file-level diff.
        return path.deletingLastPathComponent == SimulatorPaths.userDefaultsPath
            && path.pathExtension == "plist"
    }

    static func domain(ofRelativePath relativePath: String) -> String {
        UserDefaultsDomain.domain(ofPreferencesFileAt: URL(fileURLWithPath: relativePath))
    }

    /// The keys that differ between two versions of one defaults domain.
    ///
    /// Either side may be `nil`, meaning the domain was added or removed outright.
    /// - Returns: `nil` when a side exists but cannot be read as a property list, so the caller can
    ///   fall back to reporting an ordinary file change rather than claiming nothing differs.
    static func changes(domain: String, oldURL: URL?, newURL: URL?) -> [SnapshotDefaultsChange]? {
        var old: [String: Any] = [:]
        var new: [String: Any] = [:]

        if let oldURL {
            guard let values = readDictionary(at: oldURL) else {
                return nil
            }

            old = values
        }
        if let newURL {
            guard let values = readDictionary(at: newURL) else {
                return nil
            }

            new = values
        }

        var changes: [SnapshotDefaultsChange] = []

        for key in Set(old.keys).union(new.keys).sorted() {
            let oldValue = old[key]
            let newValue = new[key]

            switch (oldValue, newValue) {
            case let (nil, .some(value)):
                changes.append(SnapshotDefaultsChange(kind: .added,
                                                      domain: domain,
                                                      key: key,
                                                      oldValue: nil,
                                                      newValue: describe(value)))
            case let (.some(value), nil):
                changes.append(SnapshotDefaultsChange(kind: .removed,
                                                      domain: domain,
                                                      key: key,
                                                      oldValue: describe(value),
                                                      newValue: nil))
            case let (.some(lhs), .some(rhs)) where !areEqual(lhs, rhs):
                changes.append(SnapshotDefaultsChange(kind: .changed,
                                                      domain: domain,
                                                      key: key,
                                                      oldValue: describe(lhs),
                                                      newValue: describe(rhs)))
            default:
                break
            }
        }

        return changes
    }

    /// Property list values come back as Foundation objects, so identity is `isEqual:` rather than
    /// Swift equality — there is no static type to compare on.
    private static func areEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        (lhs as AnyObject).isEqual(rhs as AnyObject)
    }

    /// A short, stable rendering for the diff output. Data is summarised by length rather than
    /// dumped: a blob of keychain-adjacent bytes in a diff is noise at best.
    private static func describe(_ value: Any) -> String {
        switch value {
        case let data as Data:
            "<\(data.count) bytes>"
        case let date as Date:
            ISO8601DateFormatter().string(from: date)
        case let string as String:
            string
        default:
            String(describing: value)
        }
    }

    /// - Returns: `nil` when the file exists but is not a readable property list.
    private static func readDictionary(at url: URL) -> [String: Any]? {
        do {
            let data = try Data(contentsOf: url)
            let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)

            return plist as? [String: Any]
        } catch {
            os_log("Snapshot diff could not read preferences at %{public}@: %{public}@",
                   url.path,
                   error.localizedDescription)

            return nil
        }
    }
}
