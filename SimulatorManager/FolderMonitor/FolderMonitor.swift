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
/// watch by choosing an appropriately narrow `url`.
final class FolderMonitor: @unchecked Sendable {
    // MARK: - Types

    enum MonitorError: Error {
        case failedToStartMonitoring(path: String)
        case alreadyMonitoring
        case notMonitoring
    }

    /// Holds the change subject for the FSEvents C callback. The stream context retains
    /// this object (via the context retain/release callbacks), so an in-flight callback
    /// can never touch deallocated memory even while the monitor itself is being torn down.
    private final class EventSink {
        private let subject: PassthroughSubject<Void, Never>

        init(subject: PassthroughSubject<Void, Never>) {
            self.subject = subject
        }

        func handleEvents() {
            subject.send(())
        }
    }

    // MARK: - Properties

    /// URL for the directory being monitored.
    let url: URL

    /// Emits on the main queue whenever a change is detected anywhere under `url`.
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

    init(url: URL, latency: TimeInterval = 1.0) {
        let subject = PassthroughSubject<Void, Never>()
        self.url = url
        self.latency = latency
        self.changeSubject = subject
        self.folderDidChange = subject.receive(on: DispatchQueue.main).eraseToAnyPublisher()
        self.sink = EventSink(subject: subject)
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

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else {
                return
            }

            let sink = Unmanaged<EventSink>.fromOpaque(info).takeUnretainedValue()
            sink.handleEvents()
        }

        guard let newStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer)
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
