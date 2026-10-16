//
//  FolderMonitor.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 15.12.23.
//

import Combine
import CoreServices
import Foundation
import os

/// Folder monitor built on FSEvents.
///
/// FSEvents is path-based rather than file-descriptor-based: it natively watches the
/// whole subtree under the given path, keeps working when the watched folder is deleted
/// and recreated (simulator erase), delivers kernel-coalesced events, and does not
/// consume a file descriptor per watched folder. Because the watch is inherently
/// recursive, the monitor signals on any change beneath `url`; callers scope what they
/// watch by choosing an appropriately narrow `url`, or — when the narrow folder does not
/// exist yet — by passing `relevantSubpaths` so changes elsewhere under `url` are ignored.
final class FolderMonitor: @unchecked Sendable {
    // MARK: - Types

    enum MonitorError: Error {
        case failedToStartMonitoring(path: String)
        case alreadyMonitoring
        case notMonitoring
    }

    /// Decides whether an FSEvents path falls inside one of the watched subtrees.
    ///
    /// Prefixes are absolute and carry both the watched path as given and its symlink-resolved
    /// form, because FSEvents reports real paths (`/var/...` arrives as `/private/var/...`).
    struct EventPathFilter: Sendable {
        let prefixes: [String]

        init(root: URL, relevantSubpaths: [String]) {
            var roots = [Self.normalized(root.standardizedFileURL.path)]
            if let resolved = realpath(root.path, nil) {
                roots.append(Self.normalized(String(cString: resolved)))
                free(resolved)
            }

            let subpaths = relevantSubpaths.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
            prefixes = Array(Set(roots.flatMap { root in subpaths.map { "\(root)/\($0)" } }))
        }

        /// A path matches when it lies inside a relevant subtree. An ancestor of one only matches
        /// when FSEvents asks for a rescan (coalesced or dropped events), since the change may
        /// then be hidden anywhere below it.
        func matches(path: String, flags: FSEventStreamEventFlags) -> Bool {
            let path = Self.normalized(path)
            let mustScanSubDirs = flags & FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs) != 0

            return prefixes.contains { prefix in
                if path == prefix || path.hasPrefix(prefix + "/") {
                    return true
                }

                return mustScanSubDirs && prefix.hasPrefix(path + "/")
            }
        }

        /// FSEvents reports directories with a trailing slash; compare without it.
        private static func normalized(_ path: String) -> String {
            path.hasSuffix("/") ? String(path.dropLast()) : path
        }
    }

    /// Holds the change subject for the FSEvents C callback. The stream context retains
    /// this object (via the context retain/release callbacks), so an in-flight callback
    /// can never touch deallocated memory even while the monitor itself is being torn down.
    private final class EventSink {
        private let subject: PassthroughSubject<Void, Never>
        private let filter: EventPathFilter?

        init(subject: PassthroughSubject<Void, Never>, filter: EventPathFilter?) {
            self.subject = subject
            self.filter = filter
        }

        func handleEvents(paths: [String], flags: [FSEventStreamEventFlags]) {
            if let filter, !zip(paths, flags).contains(where: { filter.matches(path: $0, flags: $1) }) {
                return
            }

            subject.send(())
        }
    }

    // MARK: - Properties

    /// URL for the directory being monitored.
    let url: URL

    /// Emits on the main queue whenever a change is detected under `url` (restricted to
    /// `relevantSubpaths` when those were given).
    /// Delivery is hopped to main (restoring the pre-FSEvents contract) so subscribers can
    /// update UI/`@Published` state directly, even though FSEvents fires on a private queue.
    let folderDidChange: AnyPublisher<Void, Never>

    private let changeSubject: PassthroughSubject<Void, Never>
    private let latency: TimeInterval
    private let sink: EventSink
    private let eventQueue = DispatchQueue(label: "FolderMonitor.events")
    private let stateLock = NSLock()
    private var stream: FSEventStreamRef?

    // MARK: - Initializers

    /// - Parameter relevantSubpaths: Paths relative to `url`. When non-empty, only changes inside
    ///   these subtrees are reported; they don't need to exist yet.
    init(url: URL, latency: TimeInterval = 1.0, relevantSubpaths: [String] = []) {
        let subject = PassthroughSubject<Void, Never>()
        self.url = url
        self.latency = latency
        self.changeSubject = subject
        self.folderDidChange = subject.receive(on: DispatchQueue.main).eraseToAnyPublisher()
        let filter = relevantSubpaths.isEmpty ? nil : EventPathFilter(root: url, relevantSubpaths: relevantSubpaths)
        self.sink = EventSink(subject: subject, filter: filter)
    }

    deinit {
        try? stopMonitoring()
    }

    // MARK: - Monitoring

    /// Start listening for changes to the directory (if we are not already).
    func startMonitoring() throws {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard stream == nil else {
            throw MonitorError.alreadyMonitoring
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(sink).toOpaque(),
            retain: { info in
                guard let info else {
                    return nil
                }

                _ = Unmanaged<EventSink>.fromOpaque(info).retain()
                return UnsafeRawPointer(info)
            },
            release: { info in
                guard let info else {
                    return
                }

                Unmanaged<EventSink>.fromOpaque(info).release()
            },
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, eventCount, eventPaths, eventFlags, _ in
            guard let info else {
                return
            }

            let sink = Unmanaged<EventSink>.fromOpaque(info).takeUnretainedValue()
            // `kFSEventStreamCreateFlagUseCFTypes` makes `eventPaths` a CFArray of CFStrings.
            let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] ?? []
            let flags = Array(UnsafeBufferPointer(start: eventFlags, count: eventCount))
            sink.handleEvents(paths: paths, flags: flags)
        }

        guard let newStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes)
        ) else {
            throw MonitorError.failedToStartMonitoring(path: url.path)
        }

        FSEventStreamSetDispatchQueue(newStream, eventQueue)

        guard FSEventStreamStart(newStream) else {
            FSEventStreamInvalidate(newStream)
            FSEventStreamRelease(newStream)
            throw MonitorError.failedToStartMonitoring(path: url.path)
        }

        stream = newStream
    }

    /// Stop listening for changes to the directory, if monitoring was started.
    func stopMonitoring() throws {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard let stream else {
            throw MonitorError.notMonitoring
        }

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
