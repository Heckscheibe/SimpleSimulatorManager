//
//  FolderEventPathFilter.swift
//  SimulatorCore
//

import Foundation

/// Decides whether an FSEvents event path concerns one folder inside a larger watched tree.
///
/// FSEvents can only watch a folder and everything beneath it. When the folder we care about does
/// not exist yet, the watch has to sit on an ancestor that does, and that ancestor may be far busier
/// than the folder itself: a booted simulator rewrites logs and caches under `data` hundreds of times
/// a second, while an app install only touches `data/Containers/Bundle/Application`. This filter
/// keeps the events that can mean the relevant folder changed and drops the rest.
///
/// An event path is relevant when it is the relevant folder, lies inside it, or is one of its
/// ancestors under the watched root. Ancestors count because creating the folder is reported on
/// its parent, and because FSEvents reports a coalesced "rescan this subtree" on an ancestor when
/// it had to drop events. A path that cannot be related to the watched root at all is treated as
/// relevant, so a surprise in how FSEvents spells a path costs a spurious refresh, never a missed one.
struct FolderEventPathFilter: Sendable, Equatable {
    /// One way of spelling the watched root, paired with the relevant folder spelled the same way.
    private struct Spelling: Sendable, Equatable {
        let root: String
        let relevantFolder: String
    }

    private let spellings: [Spelling]

    /// - Returns: `nil` when `relevantFolder` is not strictly inside `watchedRoot`; such a filter
    ///   could only drop events the watch exists for, or would filter nothing at all.
    init?(watchedRoot: URL, relevantFolder: URL) {
        // Plain paths, deliberately not `standardizedFileURL`: that strips `/private` from a path
        // only when it exists, so an existing root and its not-yet-created folder would come out
        // spelled differently and never match.
        let root = Self.normalized(watchedRoot.path)
        let relevant = Self.normalized(relevantFolder.path)

        guard relevant != root, relevant.hasPrefix(Self.directoryPrefix(root)) else {
            return nil
        }

        let relativePath = String(relevant.dropFirst(root.count))

        // FSEvents reports resolved paths, so a root reached through a symlink (`/var/folders/…` is
        // really `/private/var/folders/…`) arrives spelled differently from how it was given. Only
        // the root needs resolving: it exists while it is watched, and the relevant folder may not.
        // `URL.resolvingSymlinksInPath()` strips `/private` again, hence `realpath`.
        var roots = [root]
        if let resolved = Self.realPath(of: root), resolved != root {
            roots.append(resolved)
        }

        spellings = roots.map { Spelling(root: $0, relevantFolder: $0 + relativePath) }
    }

    func isRelevant(eventPath: String) -> Bool {
        let path = Self.normalized(eventPath)

        guard let spelling = spellings.first(where: { path == $0.root || path.hasPrefix(Self.directoryPrefix($0.root)) }) else {
            // Not under any known spelling of the root: forward rather than risk missing a change.
            return true
        }

        let relevantFolder = spelling.relevantFolder
        return path == relevantFolder
            || path.hasPrefix(Self.directoryPrefix(relevantFolder))
            || relevantFolder.hasPrefix(Self.directoryPrefix(path))
    }

    // MARK: - Path helpers

    /// FSEvents reports directory paths with a trailing slash, the root without one.
    private static func normalized(_ path: String) -> String {
        guard path.count > 1, path.hasSuffix("/") else {
            return path
        }

        return String(path.dropLast())
    }

    /// The prefix every path strictly inside `path` starts with. Comparing against it, rather than
    /// `path` itself, keeps a sibling such as `ApplicationX` from passing for `Application`.
    private static func directoryPrefix(_ path: String) -> String {
        path == "/" ? path : path + "/"
    }

    private static func realPath(of path: String) -> String? {
        guard let resolved = realpath(path, nil) else {
            return nil
        }

        defer { free(resolved) }
        return normalized(String(cString: resolved))
    }
}
