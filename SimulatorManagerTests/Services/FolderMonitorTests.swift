//
//  FolderMonitorTests.swift
//  SimulatorManagerTests
//

import Combine
import Foundation
import Testing
@testable import SimulatorManager

@Suite("FolderMonitor", .serialized)
struct FolderMonitorTests {
    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("FolderMonitorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func waitForChange(of monitor: FolderMonitor, timeout: TimeInterval = 5.0) async -> Bool {
        await withCheckedContinuation { continuation in
            var cancellable: AnyCancellable?
            let hasResumed = OnceFlag()

            cancellable = monitor.folderDidChange
                .sink {
                    if hasResumed.trySet() {
                        cancellable?.cancel()
                        continuation.resume(returning: true)
                    }
                }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if hasResumed.trySet() {
                    cancellable?.cancel()
                    continuation.resume(returning: false)
                }
            }
        }
    }

    @Test("Detects a new file in the watched folder")
    func detectsDirectChange() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let monitor = FolderMonitor(url: directory, recursive: false, latency: 0.1)
        try monitor.startMonitoring()

        async let changed = waitForChange(of: monitor)
        try? await Task.sleep(nanoseconds: 100_000_000)
        try "content".write(to: directory.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)

        #expect(await changed)
        try monitor.stopMonitoring()
    }

    @Test("Detects deep changes when recursive")
    func detectsRecursiveChange() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let nested = directory
            .appendingPathComponent("level1", isDirectory: true)
            .appendingPathComponent("level2", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let monitor = FolderMonitor(url: directory, recursive: true, latency: 0.1)
        try monitor.startMonitoring()

        async let changed = waitForChange(of: monitor)
        try? await Task.sleep(nanoseconds: 100_000_000)
        try "content".write(to: nested.appendingPathComponent("deep.txt"), atomically: true, encoding: .utf8)

        #expect(await changed)
        try monitor.stopMonitoring()
    }

    // Note: there is deliberately no "ignores deep changes when not recursive" test.
    // FSEvents only provides file-level event granularity on a best-effort basis and
    // may coalesce to directory-level events, so a strict negative assertion is flaky.

    @Test("Start and stop lifecycle guards")
    func lifecycleGuards() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let monitor = FolderMonitor(url: directory, latency: 0.1)

        #expect(throws: FolderMonitor.MonitorError.self) {
            try monitor.stopMonitoring()
        }

        try monitor.startMonitoring()

        #expect(throws: FolderMonitor.MonitorError.self) {
            try monitor.startMonitoring()
        }

        try monitor.stopMonitoring()

        // Restart after a stop must work
        try monitor.startMonitoring()
        try monitor.stopMonitoring()
    }
}

/// Tiny thread-safe once-flag for test continuations.
private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    /// Returns true exactly once.
    func trySet() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else {
            return false
        }

        resumed = true
        return true
    }
}
