# Integrated Folder Monitoring Implementation

This implementation provides app change monitoring integrated directly into the existing architecture using the established AppFolderMonitor pattern.

## Architecture Overview

### 1. FolderMonitor Class (FSEvents-based)
The base `FolderMonitor` class uses macOS's FSEvents API (`FSEventStreamCreate` scheduled on a private dispatch queue) to monitor filesystem changes:

- **Path-based monitoring**: FSEvents watches paths rather than file descriptors, so monitoring survives the watched folder being deleted and recreated (e.g. simulator erase) and consumes no file descriptors
- **Inherently recursive**: FSEvents watches the whole subtree under the given path, so any change beneath it is detected. Callers scope what they observe by choosing a narrow enough `url` (the app packages folder once apps exist, otherwise the data folder). There is no separate non-recursive mode — an FSEvents stream is always recursive
- **Kernel-coalesced events**: FSEvents batches rapid changes via its latency parameter; no manual directory rescans or modification-date caches are needed
- **Main-queue delivery**: `folderDidChange` hops to the main queue via `receive(on:)` so subscribers may update UI/`@Published` state directly
- **Teardown safety**: the FSEvents stream context retains a small `EventSink` object (not the monitor itself), so in-flight callbacks can never touch deallocated memory

### 2. AppFolderMonitor Integration
Uses the existing `AppFolderMonitor` class that was already in the project:

- **Device-specific monitoring**: each device gets its own monitor for its app packages folder, or its data folder (recursively) while no app is installed yet
- **Debounced notifications**: 3-second debounce to avoid excessive updates during bulk operations
- **Automatic lifecycle**: monitors start automatically and are cleaned up when devices are removed

### 3. DeviceAppMonitoringService
Main-actor-isolated service that owns the per-device monitors:

- **Paired lifecycle**: each monitor is stored together with its Combine subscription, so recreating a monitor also releases the old subscription
- **Change detection**: `computeAppChanges` diffs the previous and current app snapshots; an app is only reported as *updated* when its `contentModifiedAt` date moved forward, so unrelated apps never flood the recent-apps list
- **Off-main refresh**: on a folder change the device is reloaded via `DeviceManager.refreshDevice(_:) async`, which performs the filesystem work on a background queue and publishes the result on the main queue
- **Resilient monitoring**: if a refresh fails, the monitor is recreated with the stale device rather than silently dropping monitoring for that device

### 4. DeviceManager
The DeviceManager continues to use the Separation of Concerns principle:

- **Simplified responsibilities**: focuses on device discovery and coordination
- **Delegated app discovery**: uses `AppDiscoveryService` for app-related operations
- **Background refreshes**: `refreshDevice(_:) async` reloads a single device off the main thread

### 5. AppDiscoveryService
The extracted service that handles:

- **App metadata extraction**: parses Info.plist files to extract app information
- **App-data correlation**: matches app bundles with their data containers
- **Change timestamps**: derives each app's `contentModifiedAt` from the newer of its data container and `.app` bundle modification dates (the bundle is replaced on install/update, making it the reliable update signal)
- **App group discovery**: finds and processes app groups

### 6. User Interface Integration
- **RecentAppsView**: SwiftUI view that displays recent app installations and removals
- **Menu bar integration**: shows at the top of the menu bar app
- **Reactive updates**: automatically refreshes when published properties change

## File Structure

```
FolderMonitor/
├── FolderMonitor.swift                # FSEvents-based filesystem monitoring
└── AppFolderMonitor.swift             # Device-specific app folder monitoring

Services/
├── AppDiscoveryService.swift          # App discovery and metadata extraction
└── DeviceAppMonitoringService.swift   # Per-device monitor lifecycle + change diffing

ViewModels/
└── SimulatorManagerViewModel.swift    # Binds device and recent-app state for the UI

Views/
└── RecentAppsView.swift               # UI for displaying recent changes

DeviceManager.swift                    # Device discovery, coordination, refreshes
```
