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
/// FSEvents is path-based rather than file-descriptor-based: it natively supports
/// recursive monitoring, keeps working when the watched folder is deleted and
/// recreated (simulator erase), delivers kernel-coalesced events, and does not
/// consume a file descriptor per watched folder.
final class FolderMonitor: @unchecked Sendable {
    // MARK: - Types

    enum MonitorError: Error {
        case failedToStartMonitoring(path: String)
        case alreadyMonitoring
        case notMonitoring
    }

    /// Holds everything the FSEvents C callback needs. The stream context retains
    /// this object (via the context retain/release callbacks), so an in-flight
    /// callback can never touch deallocated memory even while the monitor itself
    /// is being torn down.
    private final class EventSink {
        let subject: PassthroughSubject<Void, Never>
        /// Symlink-resolved path of the watched folder, for comparison against
        /// event paths (FSEvents reports resolved paths, e.g. `/private/var/…`).
        let watchedPath: String
        let recursive: Bool

        init(subject: PassthroughSubject<Void, Never>, watchedPath: String, recursive: Bool) {
            self.subject = subject
            self.watchedPath = watchedPath
            self.recursive = recursive
        }

        /// Non-recursive filtering is best-effort: FSEvents delivers file-level paths
        /// when possible but may coalesce to directory-level events, in which case we
        /// signal anyway. A spurious signal only costs one debounced device refresh.
        func handleEvents(paths: [String]) {
            guard !recursive else {
                subject.send(())
                return
            }

            // Non-recursive: only react to changes of the folder itself or its direct children.
            for path in paths {
                let standardized = (path as NSString).standardizingPath
                if standardized == watchedPath ||
                    (standardized as NSString).deletingLastPathComponent == watchedPath {
                    subject.send(())
                    return
                }
            }
        }
    }

    // MARK: - Properties

    /// URL for the directory being monitored.
    let url: URL

    /// Emits whenever a relevant change is detected. Events are sent from a private
    /// queue; subscribers that update UI state must hop to the main queue.
    let folderDidChange: PassthroughSubject<Void, Never>

    private let recursive: Bool
    private let latency: TimeInterval
    private let sink: EventSink
    private let eventQueue = DispatchQueue(label: "FolderMonitor.events")
    private let stateLock = NSLock()
    private var stream: FSEventStreamRef?

    // MARK: - Initializers

    init(url: URL, recursive: Bool = false, latency: TimeInterval = 1.0) {
        let subject = PassthroughSubject<Void, Never>()
        self.url = url
        self.recursive = recursive
        self.latency = latency
        self.folderDidChange = subject
        self.sink = EventSink(
            subject: subject,
            // Normalize the same way event paths are normalized in handleEvents,
            // so /var vs. /private/var style differences cannot break the comparison.
            watchedPath: (url.resolvingSymlinksInPath().path as NSString).standardizingPath,
            recursive: recursive
        )
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

        let callback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
            guard let info else {
                return
            }

            let sink = Unmanaged<EventSink>.fromOpaque(info).takeUnretainedValue()
            let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] ?? []
            sink.handleEvents(paths: paths)
        }

        let flags = kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer

        guard let newStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            FSEventStreamCreateFlags(flags)
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
