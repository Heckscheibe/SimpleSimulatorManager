//
//  FolderMonitor.swift
//  SimulatorManager
//
//  Created by Nicolas Hiller on 15.12.23.
//

import Foundation
import Combine

/// Enhanced folder monitor that provides detailed change information
/// Originally based on https://medium.com/over-engineering/monitoring-a-folder-for-changes-in-ios-dc3f8614f902
/// but updated using Combine publishers and enhanced for simulator app monitoring
final class FolderMonitor: Sendable {
    // MARK: - Types
    
    enum ChangeType {
        case added
        case modified
        case deleted
    }
    
    struct FolderChange {
        let changeType: ChangeType
        let url: URL
        let timestamp: Date
    }
    
    enum MonitorError: Error {
        case failedToOpenDirectory(path: String)
        case alreadyMonitoring
        case notMonitoring
    }
    
    // MARK: Properties
    
    /// A file descriptor for the monitored directory.
    private var monitoredFolderFileDescriptor: CInt = -1
    /// A dispatch queue used for sending file changes in the directory.
    private let folderMonitorQueue = DispatchQueue(label: "FolderMonitorQueue", attributes: .concurrent)
    /// A dispatch source to monitor a file descriptor created from the directory.
    private var folderMonitorSource: DispatchSourceFileSystemObject?
    /// URL for the directory being monitored.
    let url: URL
    
    /// Recursively monitor subdirectories
    private let recursive: Bool
    
    /// Cache of file modification dates for comparison
    private var fileModificationCache: [URL: Date] = [:]
    private let cacheQueue = DispatchQueue(label: "FolderMonitor.cacheQueue", attributes: .concurrent)
    
    // MARK: - Publishers
    
    /// Simple change notification (backward compatibility)
    var folderDidChange: PassthroughSubject<Void, Never> = .init()
    
    /// Detailed change information
    var detailedChanges: PassthroughSubject<[FolderChange], Never> = .init()
    
    /// Error notifications
    var errors: PassthroughSubject<MonitorError, Never> = .init()
    
    // MARK: Initializers
    
    init(url: URL, recursive: Bool = false) {
        self.url = url
        self.recursive = recursive
        self.buildInitialCache()
    }
    
    // MARK: - Private Methods
    
    private func buildInitialCache() {
        cacheQueue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            self.fileModificationCache = self.scanDirectory(at: self.url)
        }
    }
    
    private func scanDirectory(at url: URL) -> [URL: Date] {
        var cache: [URL: Date] = [:]
        
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: recursive ? [] : [.skipsSubdirectoryDescendants]
        ) else {
            return cache
        }
        
        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
                if let modificationDate = resourceValues.contentModificationDate {
                    cache[fileURL] = modificationDate
                }
            } catch {
                // Skip files we can't read
                continue
            }
        }
        
        return cache
    }
    
    private func detectChanges() {
        cacheQueue.async { [weak self] in
            guard let self else { return }
            
            let currentState = self.scanDirectory(at: self.url)
            var changes: [FolderChange] = []
            
            // Find new or modified files
            for (url, modificationDate) in currentState {
                if let cachedDate = self.fileModificationCache[url] {
                    if modificationDate > cachedDate {
                        changes.append(FolderChange(changeType: .modified, url: url, timestamp: modificationDate))
                    }
                } else {
                    changes.append(FolderChange(changeType: .added, url: url, timestamp: modificationDate))
                }
            }
            
            // Find deleted files
            for (url, _) in self.fileModificationCache where currentState[url] == nil {
                changes.append(FolderChange(changeType: .deleted, url: url, timestamp: Date()))
            }
            
            // Update cache
            self.fileModificationCache = currentState
            
            // Notify subscribers
            if !changes.isEmpty {
                DispatchQueue.main.async {
                    self.folderDidChange.send(())
                    self.detailedChanges.send(changes)
                }
            }
        }
    }

    // MARK: Monitoring
    /// Listen for changes to the directory (if we are not already).
    func startMonitoring() throws {
        guard folderMonitorSource == nil,
              monitoredFolderFileDescriptor == -1 else {
            throw MonitorError.alreadyMonitoring
        }
        
        // Open the directory referenced by URL for monitoring only.
        monitoredFolderFileDescriptor = open(url.path, O_EVTONLY)
        
        guard monitoredFolderFileDescriptor != -1 else {
            throw MonitorError.failedToOpenDirectory(path: url.path)
        }
        
        // Define a dispatch source monitoring the directory for additions, deletions, and renamings.
        folderMonitorSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: monitoredFolderFileDescriptor,
            eventMask: [.write, .delete],
            queue: folderMonitorQueue
        )
        
        // Define the block to call when a file change is detected.
        folderMonitorSource?.setEventHandler { [weak self] in
            self?.detectChanges()
        }
        
        // Define a cancel handler to ensure the directory is closed when the source is cancelled.
        folderMonitorSource?.setCancelHandler { [weak self] in
            guard let strongSelf = self else { return }
            close(strongSelf.monitoredFolderFileDescriptor)
            strongSelf.monitoredFolderFileDescriptor = -1
            strongSelf.folderMonitorSource = nil
        }
        
        // Start monitoring the directory via the source.
        folderMonitorSource?.resume()
    }

    /// Stop listening for changes to the directory, if the source has been created.
    func stopMonitoring() throws {
        guard folderMonitorSource != nil else {
            throw MonitorError.notMonitoring
        }
        folderMonitorSource?.cancel()
    }
    
    // MARK: - Cleanup
    
    deinit {
        try? stopMonitoring()
    }
}
