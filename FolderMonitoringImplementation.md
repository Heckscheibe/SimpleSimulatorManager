# Integrated Folder Monitoring Implementation

This implementation provides app change monitoring integrated directly into the existing architecture using the established AppFolderMonitor pattern.

## Architecture Overview

### 1. Enhanced FolderMonitor Class
The base `FolderMonitor` class uses macOS's `DispatchSource.makeFileSystemObjectSource` to monitor filesystem events:

- **Low-level monitoring**: Uses file descriptors and dispatch sources for efficient filesystem event detection
- **Event types**: Monitors for `.write`, `.delete`, `.rename`, and `.extend` events
- **Detailed change tracking**: Provides specific information about what changed (added, modified, deleted)
- **Combine integration**: Uses `PassthroughSubject` for reactive programming patterns

### 2. AppFolderMonitor Integration
Uses the existing `AppFolderMonitor` class that was already in the project:

- **Device-specific monitoring**: Each device gets its own monitor for `device.appContainerFolder`
- **Debounced notifications**: 3-second debounce to avoid excessive updates during bulk operations
- **Automatic lifecycle**: Monitors start automatically and are cleaned up when devices are removed
- **Established pattern**: Leverages the existing monitoring pattern used throughout the app

### 3. Integrated SimulatorManagerViewModel
Enhanced the existing ViewModel to include app change tracking:

- **Unified responsibility**: Single ViewModel handles both device management and change tracking
- **Published properties**: `@Published var recentAppChanges` for reactive UI updates
- **Existing integration**: Uses the same AppFolderMonitor pattern already established
- **Device updates**: Automatically refreshes device data when changes are detected

### 4. Refactored DeviceManager
The DeviceManager continues to use the Separation of Concerns principle:

- **Simplified responsibilities**: Focuses on device discovery and coordination
- **Delegated app discovery**: Uses `AppDiscoveryService` for app-related operations
- **Shared instance**: Can be injected into multiple services for consistency

### 5. AppDiscoveryService
The extracted service that handles:

- **App metadata extraction**: Parses Info.plist files to extract app information
- **App-data correlation**: Matches app bundles with their data containers
- **App group discovery**: Finds and processes app groups
- **Proper model usage**: Uses existing `SimulatoriOSApp` and `SimulatorWatchOSApp` models

### 6. User Interface Integration
- **RecentAppsView**: SwiftUI view that displays recent app installations and removals
- **Enhanced information**: Shows app name, bundle ID, device name, and change type (installed/removed)
- **Menu bar integration**: Shows at the top of your existing menu bar app
- **Settings integration**: Can be toggled on/off via preferences
- **Context menus**: Right-click options for opening in Finder, copying bundle IDs, etc.
- **Reactive updates**: Automatically refreshes when the ViewModel's published properties change

## Key Improvements Over Separate Service Approach

### Better Architecture
- **Unified ViewModel**: Single ViewModel handles both device management and change tracking
- **Existing patterns**: Uses the established AppFolderMonitor pattern already in the codebase
- **Reactive UI**: Published properties automatically trigger UI updates
- **Simplified dependencies**: No separate service to inject and manage

### Enhanced Integration
- **Device context**: Each app change includes the device where it occurred
- **Focused detection**: Only tracks app installations and removals, not internal file changes
- **Efficient monitoring**: Uses the proven AppFolderMonitor with debouncing
- **Proper app metadata**: Leverages existing, battle-tested app discovery logic
- **Watch app detection**: Properly identifies iOS/watchOS app relationships

### Performance Optimizations
- **Shared device discovery**: No duplicate scanning of simulator directories
- **Debounced monitoring**: 3-second debounce prevents excessive updates during bulk operations
- **Established monitoring**: Uses the same AppFolderMonitor pattern already proven in the app
- **Automatic lifecycle**: Monitors are created and destroyed as devices come and go
- **Minimal resource usage**: Leverages existing monitoring infrastructure

## File Structure

```
FolderMonitor/
├── FolderMonitor.swift                # Enhanced filesystem monitoring
└── AppFolderMonitor.swift             # Device-specific app folder monitoring (existing)

Services/
└── AppDiscoveryService.swift          # App discovery and metadata extraction

ViewModels/
└── SimulatorManagerViewModel.swift    # Enhanced with app change tracking

Views/
└── RecentAppsView.swift               # UI for displaying recent changes

DeviceManager.swift                    # Refactored device management
```

## Usage

### Basic Setup
```swift
let deviceManager = DeviceManager()
let viewModel = SimulatorManagerViewModel(deviceManager: deviceManager)

// Subscribe to changes
viewModel.$recentAppChanges
    .sink { changes in
        // Handle app changes with device context
    }
    .store(in: &cancellables)
```

### Integration Points
The monitoring is automatically integrated into your existing app flow:
- ViewModels are already set up with the enhanced functionality
- UI components automatically refresh when changes occur
- Settings integration already works with the new feature

## Benefits of Integrated Architecture

1. **Code reuse**: Leverages existing AppFolderMonitor pattern
2. **Consistency**: Uses the same models and monitoring approach throughout the app
3. **Maintainability**: Single ViewModel responsible for related functionality
4. **Simplicity**: No separate services to manage and inject
5. **Performance**: Uses established, efficient monitoring patterns
6. **User Experience**: Automatic UI updates and device context for each change
7. **Recent apps priority**: Most recently installed apps appear at the top of the list

This integrated implementation maintains all the monitoring functionality while being perfectly aligned with your existing codebase patterns and requiring minimal additional complexity.
