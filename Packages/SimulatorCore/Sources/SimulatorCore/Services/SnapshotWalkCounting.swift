//
//  SnapshotWalkCounting.swift
//  SimulatorManager
//

import Foundation

/// Counts how often a container is walked, and how many file headers those walks read.
///
/// A scoped walk opens every candidate file to read its header, so the number of walks a capture
/// takes is its cost. This makes that number testable. Nothing in the app registers a container,
/// so outside tests a walk pays one dictionary lookup and records nothing.
///
/// Keyed by container path rather than global, so tests running in parallel each count only the
/// walks of their own containers.
enum SnapshotWalkCounting {
    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var walkCount = 0
        private var headerReadCount = 0

        var walks: Int {
            lock.withLock { walkCount }
        }

        var headerReads: Int {
            lock.withLock { headerReadCount }
        }

        func recordWalk() {
            lock.withLock { walkCount += 1 }
        }

        func recordHeaderRead() {
            lock.withLock { headerReadCount += 1 }
        }
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var counters: [String: Counter] = [:]

    /// Starts counting walks rooted at `containerURL`.
    static func startCounting(_ containerURL: URL) -> Counter {
        let counter = Counter()
        lock.withLock { counters[key(for: containerURL)] = counter }

        return counter
    }

    static func stopCounting(_ containerURL: URL) {
        _ = lock.withLock { counters.removeValue(forKey: key(for: containerURL)) }
    }

    /// The counter for a walk rooted at `containerURL`, when one was started.
    static func counter(for containerURL: URL) -> Counter? {
        lock.withLock { counters.isEmpty ? nil : counters[key(for: containerURL)] }
    }

    private static func key(for containerURL: URL) -> String {
        containerURL.standardizedFileURL.path
    }
}
