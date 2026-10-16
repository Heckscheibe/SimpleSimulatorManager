//
//  FolderMonitorTests.swift
//  SimulatorManagerTests
//

import Combine
import CoreServices
import Foundation
import Testing
@testable import SimulatorManager
@testable import SimulatorCore

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

        let monitor = FolderMonitor(url: directory, latency: 0.1)
        try monitor.startMonitoring()

        async let changed = waitForChange(of: monitor)
        try? await Task.sleep(nanoseconds: 100_000_000)
        try "content".write(to: directory.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)

        #expect(await changed)
        try monitor.stopMonitoring()
    }

    @Test("Detects deep changes anywhere under the watched folder")
    func detectsDeepChange() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let nested = directory
            .appendingPathComponent("level1", isDirectory: true)
            .appendingPathComponent("level2", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let monitor = FolderMonitor(url: directory, latency: 0.1)
        try monitor.startMonitoring()

        async let changed = waitForChange(of: monitor)
        try? await Task.sleep(nanoseconds: 100_000_000)
        try "content".write(to: nested.appendingPathComponent("deep.txt"), atomically: true, encoding: .utf8)

        #expect(await changed)
        try monitor.stopMonitoring()
    }

    @Test("Change notifications are delivered on the main queue")
    func deliversOnMainQueue() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let monitor = FolderMonitor(url: directory, latency: 0.1)
        try monitor.startMonitoring()

        let onMain = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let hasResumed = OnceFlag()
            var cancellable: AnyCancellable?
            cancellable = monitor.folderDidChange
                .sink {
                    if hasResumed.trySet() {
                        cancellable?.cancel()
                        continuation.resume(returning: Thread.isMainThread)
                    }
                }

            DispatchQueue.global().asyncAfter(deadline: .now() + 5.0) {
                if hasResumed.trySet() {
                    cancellable?.cancel()
                    continuation.resume(returning: false)
                }
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                try? "content".write(to: directory.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
            }
        }

        #expect(onMain)
        try monitor.stopMonitoring()
    }

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

    // MARK: - Subpath filtering

    @Test("Ignores changes outside the relevant subpaths")
    func ignoresChangesOutsideRelevantSubpaths() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let noisy = directory.appendingPathComponent("Library/Caches", isDirectory: true)
        try FileManager.default.createDirectory(at: noisy, withIntermediateDirectories: true)

        let monitor = FolderMonitor(url: directory, latency: 0.1, relevantSubpaths: ["Containers/Bundle/Application"])
        try monitor.startMonitoring()

        async let changed = waitForChange(of: monitor, timeout: 1.5)
        try? await Task.sleep(nanoseconds: 100_000_000)
        for index in 0 ..< 5 {
            try "noise".write(to: noisy.appendingPathComponent("file-\(index).txt"), atomically: true, encoding: .utf8)
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        // A sibling that only shares a string prefix with the relevant subpath is still outside it.
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("Containers/Bundle/ApplicationCache"),
                                                withIntermediateDirectories: true)

        #expect(await changed == false)
        try monitor.stopMonitoring()
    }

    @Test("Reports changes inside a relevant subpath created after monitoring started")
    func reportsChangesInsideLateCreatedSubpath() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let monitor = FolderMonitor(url: directory, latency: 0.1, relevantSubpaths: ["Containers/Bundle/Application"])
        try monitor.startMonitoring()

        async let changed = waitForChange(of: monitor)
        try? await Task.sleep(nanoseconds: 100_000_000)
        let appFolder = directory.appendingPathComponent("Containers/Bundle/Application/\(UUID().uuidString)/Test.app",
                                                         isDirectory: true)
        try FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        try "plist".write(to: appFolder.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)

        #expect(await changed)
        try monitor.stopMonitoring()
    }

    @Test("Subpath filtering works when the watched URL goes through a symlink")
    func filtersThroughSymlinkedRoot() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let realRoot = directory.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: realRoot, withIntermediateDirectories: true)
        let linkedRoot = directory.appendingPathComponent("link", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linkedRoot, withDestinationURL: realRoot)

        // FSEvents reports the resolved path, so the filter must match it rather than the link.
        let monitor = FolderMonitor(url: linkedRoot, latency: 0.1, relevantSubpaths: ["Containers/Bundle/Application"])
        try monitor.startMonitoring()

        async let changed = waitForChange(of: monitor)
        try? await Task.sleep(nanoseconds: 100_000_000)
        try FileManager.default.createDirectory(at: linkedRoot.appendingPathComponent("Containers/Bundle/Application/App"),
                                                withIntermediateDirectories: true)

        #expect(await changed)
        try monitor.stopMonitoring()
    }

    @Test("Event path filter matches the subtree, not siblings or plain ancestors")
    func eventPathFilterMatching() {
        let root = URL(fileURLWithPath: "/sim/data", isDirectory: true)
        let filter = FolderMonitor.EventPathFilter(root: root, relevantSubpaths: ["Containers/Bundle/Application"])
        let none = FSEventStreamEventFlags(kFSEventStreamEventFlagNone)
        let mustScan = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)

        #expect(filter.matches(path: "/sim/data/Containers/Bundle/Application/", flags: none))
        #expect(filter.matches(path: "/sim/data/Containers/Bundle/Application/UUID/App.app", flags: none))
        #expect(!filter.matches(path: "/sim/data/Containers/Bundle/ApplicationCache/", flags: none))
        #expect(!filter.matches(path: "/sim/data/Containers/Data/PluginKitPlugin/UUID/", flags: none))
        #expect(!filter.matches(path: "/sim/data/Library/Preferences/", flags: none))
        #expect(!filter.matches(path: "/sim/data/Containers/", flags: none))

        // A rescan request on an ancestor may hide an install, so it counts; one elsewhere does not.
        #expect(filter.matches(path: "/sim/data/Containers/", flags: mustScan))
        #expect(filter.matches(path: "/", flags: mustScan))
        #expect(!filter.matches(path: "/sim/data/Library/", flags: mustScan))
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
