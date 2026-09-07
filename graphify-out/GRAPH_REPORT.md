# Graph Report - SimpleSimulatorManager  (2026-09-07)

## Corpus Check
- 106 files · ~60,036 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1099 nodes · 2650 edges · 54 communities (48 shown, 6 thin omitted)
- Extraction: 90% EXTRACTED · 10% INFERRED · 0% AMBIGUOUS · INFERRED: 271 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `93a7cc71`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- Device Model and Test Fixtures
- Cleanup Candidate Construction
- SwiftUI View Layer
- App Change and Cleanup Enums
- Carbon Global Hotkey Registration
- FSEvents Folder Monitoring
- Device Actions and Erase Flow
- Device App Monitoring Service
- Test Suite Documentation
- GitHub Release Update Check
- Container Shortcuts and Finder Opening
- Simulator Platform Identification
- Settings and Platform Visibility
- DeviceManager and Plist Decoding
- Shortcut Recorder View Model Tests
- Menu Presenter Test Double
- Contributor and Agent Instructions
- Module Imports and File Index
- AppKit Key Capture Bridge
- Device and App Group Plists
- Test Target File Index
- Protocol Seams and MVVM Layering
- Error Reporting and Pasteboard
- Menu Bar Status Item Presenter
- Menu Bar Dropdown Screenshot
- Settings Window Screenshot
- Shortcut Recording View Model
- Global Shortcut Persistence Tests
- Shortcut Controller Wiring
- Simulator Reset Service
- Project Docs and Design Rationale
- Fastlane Signing and Release Docs
- UserDefaults Export and Fixtures
- Device Plist Coding Keys
- App Entry Point and Targets
- Recent Apps Menu Screenshot
- App Info Plist and Target Platform
- Cleanup Simulators Menu Screenshot
- Container Copy Test Doubles
- Settings Binding Helper
- View Model Edge Case Tests
- Issue, Branch and PR Workflow
- Folder Monitoring Rationale
- Release Build Script
- SwiftFormat and SwiftLint Phases
- View Model Publisher Tests
- UserDefaults Domain Filtering
- Cleanup Directory Sizing Tests
- Cleanup Service and Simulator Paths
- Global Shortcut File Index
- simctl Response Decoding
- Folder Monitoring Implementation Doc
- Pull Request Template
- Device Fixture Directory

## God Nodes (most connected - your core abstractions)
1. `String` - 137 edges
2. `Foundation` - 83 edges
3. `Device` - 58 edges
4. `Settings` - 43 edges
5. `GlobalShortcut` - 41 edges
6. `SimulatorManager` - 36 edges
7. `DeviceManager` - 35 edges
8. `MockDeviceManager` - 34 edges
9. `SimulatorManagerViewModel` - 33 edges
10. `SimulatorCleanupCandidate` - 32 edges

## Surprising Connections (you probably didn't know these)
- `DeviceAppMonitoring` --references--> `DeviceAppMonitoringServiceProtocol`  [AMBIGUOUS]
  SimulatorManager/Services/DeviceAppMonitoringService.swift → SimulatorManagerTests/README.md
- `DeviceManaging` --references--> `DeviceManagerProtocol`  [AMBIGUOUS]
  SimulatorManager/DeviceManager.swift → SimulatorManagerTests/README.md
- `Settings` --conceptually_related_to--> `Hide Recent Apps Toggle`  [INFERRED]
  SimulatorManager/Settings.swift → Screenshots/Screenshot 2.jpeg
- `Settings` --conceptually_related_to--> `Hide watchOS Toggle`  [INFERRED]
  SimulatorManager/Settings.swift → Screenshots/Screenshot 2.jpeg
- `DeviceManager` --references--> `Simulator Device List (Watch/iPhone entries)`  [INFERRED]
  SimulatorManager/DeviceManager.swift → Screenshots/Screenshot 2.jpeg

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Match Signing, Notarization and Release Pipeline** — fastlane_readme_md_env_file, fastlane_readme_md_match_password, fastlane_readme_md_app_store_connect_api_key, fastlane_readme_md_certificates_repo, fastlane_readme_md_lane_build, fastlane_readme_md_lane_release, fastlane_readme_md_notarization_stapling [EXTRACTED 1.00]
- **Cascading Cleanup Simulators Deletion Flow** — screenshots_screenshot_1_cleanup_simulators_menu, screenshots_screenshot_1_ios_26_1_device_type_submenu, screenshots_screenshot_1_delete_simulator_detail_panel, screenshots_screenshot_1_missing_runtime_deletion_reason [EXTRACTED 0.90]
- **Recent App Detail Access Flow** — screenshots_screenshot_2_exampleapp_row, screenshots_screenshot_2_documentsfolder_item, screenshots_screenshot_2_apppackage_item [EXTRACTED 1.00]
- **Platform Visibility Filter Toggles (watchOS/iPadOS/iOS)** — screenshots_screenshot_2_hidewatchos_toggle, screenshots_screenshot_2_showipados_toggle, screenshots_screenshot_2_hideios_toggle [INFERRED 0.85]
- **Simulator Maintenance Actions (Cleanup / Reset)** — screenshots_screenshot_2_cleanupsimulators_menuitem, screenshots_screenshot_2_resetallsimulators_menuitem, simulatormanager_services_simulatorresetservice_simulatorresetservice [INFERRED 0.80]
- **Settings Window: Shortcut + Per-Platform Menu Toggles** — screenshots_screenshot_3_settingswindow, screenshots_screenshot_3_globalshortcutsection, screenshots_screenshot_3_menucontentssection [EXTRACTED 1.00]
- **Per-Platform Menu Content Toggles** — screenshots_screenshot_3_iostoggle, screenshots_screenshot_3_ipadostoggle, screenshots_screenshot_3_watchostoggle, screenshots_screenshot_3_tvostoggle, screenshots_screenshot_3_visionostoggle [INFERRED 0.85]

## Communities (54 total, 6 thin omitted)

### Community 0 - "Device Model and Test Fixtures"
Cohesion: 0.17
Nodes (11): Int, Device, Bool, Date, URL, DeviceState, off, running (+3 more)

### Community 1 - "Cleanup Candidate Construction"
Cohesion: 0.10
Nodes (26): Decodable, Equatable, Sendable, FileManager, CleanupDevicePlist, MetadataStatus, decoded, missingDevicePlist (+18 more)

### Community 2 - "SwiftUI View Layer"
Cohesion: 0.10
Nodes (16): Actions, Simulator Device List (Watch/iPhone entries), ShortcutKeys, AppGroupsView, AppShortcutMenuItems, AppsView, CleanupSimulatorsView, DeviceTypeView (+8 more)

### Community 3 - "App Change and Cleanup Enums"
Cohesion: 0.08
Nodes (36): Duration, MockSimulatorCleanupService, SimulatorCleanupCandidate, SimulatorCleanupDeletionMethod, simctlDelete, trashDirectory, SimulatorCleanupReason, missingDevicePlist (+28 more)

### Community 4 - "Carbon Global Hotkey Registration"
Cohesion: 0.08
Nodes (24): EventHandlerCallRef, EventHandlerRef, EventHotKeyID, EventHotKeyRef, EventRef, OSStatus, GlobalShortcut, Bool (+16 more)

### Community 5 - "FSEvents Folder Monitoring"
Cohesion: 0.11
Nodes (20): FSEventStreamRef, AppFolderMonitor, AnyCancellable, Bool, Never, PassthroughSubject, Set, EventSink (+12 more)

### Community 6 - "Device Actions and Erase Flow"
Cohesion: 0.36
Nodes (5): SimulatorDeviceAction, erase, DeviceViewModel, Bool, DeviceViewModelTests

### Community 7 - "Device App Monitoring Service"
Cohesion: 0.17
Nodes (6): DeviceAppMonitoringService, MonitoredDevice, AnyCancellable, Date, DeviceAppMonitoringServiceTests, Date

### Community 8 - "Test Suite Documentation"
Cohesion: 0.13
Nodes (21): Auto-Generated fastlane README, Available Actions, Installation, Mac, mac build, mac bump_homebrew_cask, mac release, mac update_signing_assets (+13 more)

### Community 9 - "GitHub Release Update Check"
Cohesion: 0.11
Nodes (15): Codable, ObservableObject, CodingKeys, body, draft, htmlUrl, id, name (+7 more)

### Community 10 - "Container Shortcuts and Finder Opening"
Cohesion: 0.05
Nodes (38): CaseIterable, Identifiable, ContainerShortcutHandling, URL, FolderOpening, URL, AppGroup, Bool (+30 more)

### Community 11 - "Simulator Platform Identification"
Cohesion: 0.18
Nodes (9): String, SimulatorPlatform, appleTV, iPad, iPhone, iPodTouch, visionPro, watch (+1 more)

### Community 12 - "Settings and Platform Visibility"
Cohesion: 0.06
Nodes (29): App, Binding, NSStatusBarButton, NSWindow, ReferenceWritableKeyPath, Scene, Settings Menu Item (Cmd ,), GlobalHotkeyServing (+21 more)

### Community 13 - "DeviceManager and Plist Decoding"
Cohesion: 0.18
Nodes (8): CurrentValueSubject, DeviceManager, LoadedDevices, AnyCancellable, AnyPublisher, Never, URL, DeviceManagerReloadTests

### Community 14 - "Shortcut Recorder View Model Tests"
Cohesion: 0.31
Nodes (4): ShortcutRecorderViewModelTests, NSEvent, UInt16, TestContext

### Community 15 - "Menu Presenter Test Double"
Cohesion: 0.18
Nodes (7): MockGlobalHotkeyService, MainActor, Void, MockMenuBarMenuPresenter, Bool, GlobalShortcutControllerTests, TestContext

### Community 16 - "Contributor and Agent Instructions"
Cohesion: 0.04
Nodes (41): Architecture, Change guidance, Commands, graphify, Issue, branch and worktree workflow, Patterns to follow, Repository, Testing (+33 more)

### Community 17 - "Module Imports and File Index"
Cohesion: 0.16
Nodes (5): Combine, CoreServices, Observation, os, PlatformText

### Community 18 - "AppKit Key Capture Bridge"
Cohesion: 0.22
Nodes (9): Context, NSView, NSViewRepresentable, KeyCaptureNSView, KeyCaptureView, ShortcutRecorderView, Bool, NSEvent (+1 more)

### Community 19 - "Device and App Group Plists"
Cohesion: 0.13
Nodes (14): CodingKey, AppGroupPlist, CodingKeys, identifier, uuid, URL, CodingKeys, mcmMetadataIdentifier (+6 more)

### Community 20 - "Test Target File Index"
Cohesion: 0.12
Nodes (5): Foundation, SimulatorManager, DeviceTypeIdentifier, Fixture, Testing

### Community 21 - "Protocol Seams and MVVM Layering"
Cohesion: 0.40
Nodes (6): AnyObject, DeviceManaging, ContainerContentCopying, DeviceAppMonitoring, SimulatorResetServing, ResetSimulatorsViewModel

### Community 22 - "Error Reporting and Pasteboard"
Cohesion: 0.12
Nodes (16): Result, ContainerContentService, URL, PasteboardWriting, SystemPasteboard, UserDefaultsExporting, AlertErrorReporter, UserFacingErrorReporting (+8 more)

### Community 23 - "Menu Bar Status Item Presenter"
Cohesion: 0.28
Nodes (6): PropertyListDecoder, CustomPropertyListDecoder, AppDiscoveryService, DataContainer, Date, URL

### Community 24 - "Menu Bar Dropdown Screenshot"
Cohesion: 0.10
Nodes (21): Menu Bar Dropdown Screenshot, App Package Menu Item, Recent App Detail Submenu, Cleanup Simulators Menu Item, Documents Folder Menu Item, ExampleApp Recent App Row (iPhone 17 Pro, iOS 26.5), GitHub Project Menu Item, Hide iOS Toggle (+13 more)

### Community 25 - "Settings Window Screenshot"
Cohesion: 0.18
Nodes (12): Clear Button, Global Shortcut Section, iOS Toggle (on), iPadOS Toggle (off), Menu Contents Section, Open Menu Shortcut Recorder (^⌥⌘S), Recent Apps Toggle (on), Reset Button (+4 more)

### Community 26 - "Shortcut Recording View Model"
Cohesion: 0.15
Nodes (14): Call Verification, Concurrent Testing, DeviceAppMonitoringServiceProtocol, DeviceManagerProtocol, DeviceManagerProtocolTests, Mock Implementations, MockDeviceAppMonitoringService, MockDeviceManager (+6 more)

### Community 27 - "Global Shortcut Persistence Tests"
Cohesion: 0.17
Nodes (7): Hasher, AppChange, ChangeType, installed, removed, updated, Date

### Community 28 - "Shortcut Controller Wiring"
Cohesion: 0.18
Nodes (10): Error, MonitorError, alreadyMonitoring, failedToStartMonitoring, notMonitoring, MockError, MockSimulatorCleanupService, Set (+2 more)

### Community 29 - "Simulator Reset Service"
Cohesion: 0.17
Nodes (11): LocalizedError, GlobalHotkeyError, alreadyInUse, eventHandlerUnavailable, missingModifier, registrationFailed, ConversionError, notSerializable (+3 more)

### Community 30 - "Project Docs and Design Rationale"
Cohesion: 0.39
Nodes (8): Copilot Instructions, Pull Request Template, SwiftLint Configuration, App Sandbox Intentionally Disabled, Global Shortcut via Carbon RegisterEventHotKey (Not a Keyboard Monitor), App Works Offline, Only GitHub Releases Check, Contributing Guide, Simple Simulator Manager README

### Community 31 - "Fastlane Signing and Release Docs"
Cohesion: 0.11
Nodes (18): 1. Install Ruby, 2. Install Dependencies, 3. Configure Environment Variables, 4. Signing Assets (via match), Build Issues, Building the App, Certificate/match Issues, Distribution Notes (+10 more)

### Community 32 - "UserDefaults Export and Fixtures"
Cohesion: 0.11
Nodes (15): Data, NSNumber, T, URL, PropertyListJSONConverter, Any, Any, URL (+7 more)

### Community 33 - "Device Plist Coding Keys"
Cohesion: 0.29
Nodes (7): CodingKeys, deviceType, lastBootedAt, name, runtime, state, udid

### Community 34 - "App Entry Point and Targets"
Cohesion: 0.18
Nodes (12): Benefits of This Approach, Best Practices, File Organization, Filesystem-Free Test Isolation, Overview, Protocols and Abstractions, Guard Subscripts with #require, Not #expect, Running Tests (+4 more)

### Community 35 - "Recent Apps Menu Screenshot"
Cohesion: 0.22
Nodes (5): MockSimulatorDeviceActionService, AnyPublisher, Error, Never, Void

### Community 36 - "App Info Plist and Target Platform"
Cohesion: 0.17
Nodes (12): AppInfoPlist, AppTargetPlatform, iphonesimulator, watchsimulator, CodingKeys, cfBundleDisplayName, cfBundleIdentifier, cfBundleName (+4 more)

### Community 37 - "Cleanup Simulators Menu Screenshot"
Cohesion: 0.40
Nodes (6): Cleanup Simulators Menu UI, Delete Simulator Detail Panel, iOS 26.1 Device Type Submenu, Missing Runtime / Unavailable Deletion Reason, Refresh Cleanup Scan Menu Item, Reset All Simulators (Destructive) Menu Item

### Community 38 - "Container Copy Test Doubles"
Cohesion: 0.38
Nodes (3): Comparable, Hashable, DeviceType

### Community 39 - "Settings Binding Helper"
Cohesion: 0.40
Nodes (3): DecodableURLContainer, MetaDataPlist, URL

### Community 40 - "View Model Edge Case Tests"
Cohesion: 0.18
Nodes (7): SimulatorManagerViewModel, AnyCancellable, Set, MockDeviceAppMonitoringService, SimulatorManagerViewModelTests, AnyCancellable, Set

### Community 41 - "Issue, Branch and PR Workflow"
Cohesion: 0.40
Nodes (3): AlertDestructiveActionConfirmer, Bool, Int

### Community 42 - "Folder Monitoring Rationale"
Cohesion: 0.67
Nodes (3): FSEvents Path-Based Monitoring Rationale, RecentAppsView, Folder Monitoring Implementation Notes

### Community 46 - "UserDefaults Domain Filtering"
Cohesion: 0.18
Nodes (4): Bool, URL, UserDefaultsDomain, UserDefaultsDomainTests

### Community 47 - "Cleanup Directory Sizing Tests"
Cohesion: 0.33
Nodes (4): DeviceFixtureDirectory, URL, SettingsMenuVisibilityTests, Int

### Community 49 - "Global Shortcut File Index"
Cohesion: 0.24
Nodes (3): AppKit, Carbon.HIToolbox, PreferencesWindow

### Community 51 - "Folder Monitoring Implementation Doc"
Cohesion: 0.20
Nodes (9): 1. FolderMonitor Class (FSEvents-based), 2. AppFolderMonitor Integration, 3. DeviceAppMonitoringService, 4. DeviceManager, 5. AppDiscoveryService, 6. User Interface Integration, Architecture Overview, File Structure (+1 more)

### Community 52 - "Pull Request Template"
Cohesion: 0.29
Nodes (6): Checklist, How this was verified, Notes for reviewers, Screenshots or recording, Summary, Type of change

## Ambiguous Edges - Review These
- `DeviceManaging` → `DeviceManagerProtocol`  [AMBIGUOUS]
  SimulatorManagerTests/README.md · relation: references
- `DeviceAppMonitoring` → `DeviceAppMonitoringServiceProtocol`  [AMBIGUOUS]
  SimulatorManagerTests/README.md · relation: references
- `iOS Toggle (on)` → `iPadOS Toggle (off)`  [AMBIGUOUS]
  Screenshots/Screenshot 3.jpeg · relation: conceptually_related_to

## Knowledge Gaps
- **164 isolated node(s):** `Repository`, `Commands`, `Patterns to follow`, `Issue, branch and worktree workflow`, `Testing` (+159 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **6 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `DeviceManaging` and `DeviceManagerProtocol`?**
  _Edge tagged AMBIGUOUS (relation: references) - confidence is low._
- **What is the exact relationship between `DeviceAppMonitoring` and `DeviceAppMonitoringServiceProtocol`?**
  _Edge tagged AMBIGUOUS (relation: references) - confidence is low._
- **What is the exact relationship between `iOS Toggle (on)` and `iPadOS Toggle (off)`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **Why does `String` connect `Simulator Platform Identification` to `Device Model and Test Fixtures`, `Cleanup Candidate Construction`, `SwiftUI View Layer`, `App Change and Cleanup Enums`, `Carbon Global Hotkey Registration`, `Device Actions and Erase Flow`, `Device App Monitoring Service`, `GitHub Release Update Check`, `Container Shortcuts and Finder Opening`, `Settings and Platform Visibility`, `Device and App Group Plists`, `Protocol Seams and MVVM Layering`, `Error Reporting and Pasteboard`, `Menu Bar Status Item Presenter`, `Menu Bar Dropdown Screenshot`, `Global Shortcut Persistence Tests`, `Shortcut Controller Wiring`, `Simulator Reset Service`, `UserDefaults Export and Fixtures`, `Device Plist Coding Keys`, `Recent Apps Menu Screenshot`, `App Info Plist and Target Platform`, `Container Copy Test Doubles`, `Settings Binding Helper`, `View Model Edge Case Tests`, `SwiftFormat and SwiftLint Phases`, `UserDefaults Domain Filtering`, `Cleanup Directory Sizing Tests`, `Cleanup Service and Simulator Paths`?**
  _High betweenness centrality (0.419) - this node is a cross-community bridge._
- **Why does `SimulatorManagerViewModel` connect `View Model Edge Case Tests` to `Device Model and Test Fixtures`, `SwiftUI View Layer`, `App Entry Point and Targets`, `Container Copy Test Doubles`, `Device Actions and Erase Flow`, `Container Shortcuts and Finder Opening`, `Simulator Platform Identification`, `Settings and Platform Visibility`, `View Model Publisher Tests`, `Cleanup Directory Sizing Tests`, `Module Imports and File Index`, `Protocol Seams and MVVM Layering`, `Menu Bar Dropdown Screenshot`, `Global Shortcut Persistence Tests`?**
  _High betweenness centrality (0.124) - this node is a cross-community bridge._
- **Why does `Foundation` connect `Test Target File Index` to `Device Model and Test Fixtures`, `Cleanup Candidate Construction`, `SwiftUI View Layer`, `App Change and Cleanup Enums`, `GitHub Release Update Check`, `Container Shortcuts and Finder Opening`, `Simulator Platform Identification`, `Module Imports and File Index`, `Device and App Group Plists`, `Error Reporting and Pasteboard`, `Menu Bar Status Item Presenter`, `Global Shortcut Persistence Tests`, `Simulator Reset Service`, `App Info Plist and Target Platform`, `Container Copy Test Doubles`, `Settings Binding Helper`, `Issue, Branch and PR Workflow`, `SwiftFormat and SwiftLint Phases`, `UserDefaults Domain Filtering`, `Cleanup Service and Simulator Paths`, `Global Shortcut File Index`?**
  _High betweenness centrality (0.100) - this node is a cross-community bridge._
- **Are the 4 inferred relationships involving `String` (e.g. with `.refreshMonitor()` and `.stopMonitoring()`) actually correct?**
  _`String` has 4 INFERRED edges - model-reasoned connections that need verification._