# Simple Simulator Manager Copilot Instructions

## Repository

- GitHub repository: https://github.com/Heckscheibe/SimpleSimulatorManager
- Product: macOS SwiftUI menu bar app for inspecting and managing apps installed in local Apple simulators
- Primary target: macOS
- App style: MenuBarExtra-based utility app, not an iOS app

## Architecture Overview

Simple Simulator Manager is a SwiftUI macOS app with a lightweight MVVM structure and service-based filesystem logic.

- App entry point: `SimulatorManagerApp` wires shared state and dependencies, including `DeviceManager`, `SimulatorResetService`, and `Settings`
- View models: Use `ObservableObject` with `@Published` properties and Combine subscriptions
- Central coordinator: `DeviceManager` is the main source of truth for simulator devices, device types, and recent installed apps
- Filesystem discovery: `AppDiscoveryService` is responsible for scanning simulator folders, reading plist metadata, and constructing app and app-group models
- Folder monitoring: `DeviceAppMonitoringService` manages per-device `AppFolderMonitor` instances and updates recent apps when simulator app containers change
- Models: `Device` is a reference type with mutable published state for apps and app groups; do not convert core models to value types without a clear architectural reason

## Key Patterns

### SwiftUI and View Models

- Keep SwiftUI views thin and focused on presentation
- Put discovery, monitoring, reset, and filesystem logic in services or managers, not directly in views
- Prefer the existing repo pattern of `ObservableObject`, `@Published`, and Combine rather than introducing Observation macros unless the codebase is intentionally migrated
- For UI-facing Combine pipelines, receive on the main queue before assigning published state
- Store subscriptions in `Set<AnyCancellable>`

### Dependency Injection and Testability

- Depend on protocols for collaborators that need mocking or substitution, following the `DeviceManaging` and `DeviceAppMonitoring` pattern
- Preserve constructor injection for view models and services where possible
- If adding a new service used by view models, add a protocol when it will be mocked in tests
- Avoid tightly coupling views to concrete filesystem or monitoring implementations

### Simulator Discovery and Filesystem Access

- The app works by scanning CoreSimulator directories under the user Library; keep path logic centralized
- Reuse existing path derivation from `Device` and `SimulatorPaths` instead of re-hardcoding directory strings in multiple places
- Use `CustomPropertyListDecoder` for plist decoding
- Handle missing files, missing folders, and decode failures defensively
- Filter out `.DS_Store` and other filesystem noise
- Prefer logging recoverable filesystem and decode failures with `os_log` instead of crashing

### App Monitoring

- Reuse `FolderMonitor` and `AppFolderMonitor` patterns for any new live update behavior
- Monitoring is device-scoped; refresh only the affected device when its app folder changes
- Preserve the recent-apps behavior in `DeviceManager`:
  - deduplicate by app bundle identifier plus device UDID
  - sort by most recent timestamp first
  - cap the recent list size
- When comparing app changes, diff bundle identifiers between previous and current app sets

### Settings and Persistence

- Persist user preferences through the `Settings` type and its `UserDefaults` suite
- Keep settings keys centralized
- When adding a new preference, update visible platform or UI behavior through `Settings` rather than scattering `UserDefaults` access across the app

### Platform Constraints

- This is a macOS app, not an iOS app
- AppKit usage is acceptable when needed for Finder or system integration
- Preserve `MenuBarExtra` information architecture unless there is a strong product reason to change it
- Do not introduce iOS-only assumptions into shared code
- visionOS simulators may appear in the UI, but app discovery behavior differs by platform; preserve those platform-specific limitations unless intentionally solving them

## Testing

- Use the Swift Testing framework with `@Suite`, `@Test`, and `#expect`
- Prefer mocks from `SimulatorManagerTests/Mocks` and factories from `SimulatorManagerTests/Helpers`
- For Combine-driven tests, allow asynchronous propagation before asserting
- Keep tests focused on reactive state updates, protocol boundaries, and behavior rather than filesystem I/O
- When adding behavior to `DeviceManager` or view models, add or update tests that cover sorting, deduplication, and edge cases

## Build and Tooling

- Keep code compatible with the Xcode project’s macOS target
- Respect the existing SwiftFormat and SwiftLint build phases
- Release automation runs through fastlane via the repository build script
- Prefer changes that stay formatter- and lint-friendly instead of relying on follow-up cleanup

## Change Guidance for Copilot

- Favor minimal, localized changes that preserve the current architecture
- Fix issues at the service or manager layer rather than patching symptoms in views
- When editing `DeviceManager`, `AppDiscoveryService`, or `DeviceAppMonitoringService`, preserve the current responsibilities and avoid moving unrelated logic across layers
- Do not remove protocol seams used for tests
- Do not replace Combine-based flows with a different state management approach unless the change is explicitly requested
- Document public-facing APIs and non-obvious behavior when introducing new abstractions