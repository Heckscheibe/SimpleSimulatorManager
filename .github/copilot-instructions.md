# Simple Simulator Manager Copilot Instructions

## Repository

- GitHub repository: https://github.com/Heckscheibe/SimpleSimulatorManager
- Product: macOS SwiftUI menu bar app for inspecting and managing apps installed in local Apple simulators
- Primary target: **macOS 15.0+** — the app target and `LSMinimumSystemVersion` are both 15.0; the project-level `MACOSX_DEPLOYMENT_TARGET` of 14.0 is only an inherited default the targets override
- App style: MenuBarExtra-based utility app, not an iOS app
- Full conventions and reasoning live in [CLAUDE.md](../CLAUDE.md); this file must stay consistent with it

## Architecture Overview

Simple Simulator Manager is a SwiftUI macOS app with a lightweight MVVM structure and service-based filesystem logic.

- App entry point: `SimulatorManagerApp` wires shared state and dependencies, including `DeviceManager`, `SimulatorResetService`, and `Settings`
- View models: `@MainActor @Observable` classes (Swift Observation), held by views with `@State`
- Central coordinator: `DeviceManager` is the main source of truth for simulator devices, device types, and recent installed apps
- Filesystem discovery: `AppDiscoveryService` is responsible for scanning simulator folders, reading plist metadata, and constructing app and app-group models
- Folder monitoring: `DeviceAppMonitoringService` manages per-device `AppFolderMonitor` instances and updates recent apps when simulator app containers change
- Models: `Device` is a reference type with mutable published state for apps and app groups; do not convert core models to value types without a clear architectural reason

## Key Patterns

### SwiftUI and View Models

- Keep SwiftUI views thin and focused on presentation
- Put discovery, monitoring, reset, and filesystem logic in services or managers, not directly in views
- Two observation patterns coexist **by layer**; follow the one that matches where you are:
  - View models in `SimulatorManager/ViewModels/` are `@MainActor @Observable`. Mark injected dependencies and non-UI state `@ObservationIgnored` (see `SimulatorManagerViewModel`)
  - The model and service layer (`DeviceManager`, `Device`, `Settings`, `GithubService`, `DeviceAppMonitoringService`) stays `ObservableObject` with `@Published` and Combine, consumed via `@StateObject`/`@ObservedObject`
- Do not unify the two: never convert a view model to `ObservableObject`, and never convert the model or service layer to `@Observable`, without a clear architectural reason
- For UI-facing Combine pipelines, receive on the main queue before assigning observed state
- Store subscriptions in `Set<AnyCancellable>` (`@ObservationIgnored` inside an `@Observable` view model)

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
- When comparing app changes, diff bundle identifiers between previous and current app sets, and treat an app as updated **only** if its `contentModifiedAt` moved forward

### Settings and Persistence

- Persist user preferences through the `Settings` type and its `UserDefaults` suite
- Keep settings keys centralized
- When adding a new preference, update visible platform or UI behavior through `Settings` rather than scattering `UserDefaults` access across the app

### Platform Constraints

- This is a macOS app, not an iOS app
- The app sandbox is intentionally **disabled** (`com.apple.security.app-sandbox = false`) — it is required for direct filesystem access to CoreSimulator directories under `~/Library`. Do not re-enable it
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

Scheme `SimulatorManager`, project `SimulatorManager.xcodeproj`:

```bash
xcodebuild -project SimulatorManager.xcodeproj -scheme SimulatorManager build
xcodebuild -project SimulatorManager.xcodeproj -scheme SimulatorManager test
```

- Keep code compatible with the Xcode project’s macOS target
- Respect the existing SwiftFormat and SwiftLint build phases
- Release automation runs through fastlane via the repository build script
- Prefer changes that stay formatter- and lint-friendly instead of relying on follow-up cleanup

## Issue, Branch and Pull Request Workflow

- Every feature branch and worktree is named after the GitHub issue it implements, using GitHub's own format: `<issue-number>-<slugified-issue-title>`, lowercase and hyphen separated (for example `49-configurable-global-keyboard-shortcut-to-open-the-menu-bar-menu`)
- If no issue exists, create it first and branch from its number. The issue is the spec: it carries what to implement *and* how to verify it, including knock-on effects and explicit out-of-scope items
- Never commit feature work directly to `develop`
- Open pull requests against `develop`, never `main`, with `Closes #<number>` in the body
- A pull request's head branch cannot be changed once opened, so the branch name has to be right before the first push
- `dependabot/*` and `release/*` keep their tool-generated names
- `.github/pull_request_template.md` pre-fills the description; fill in the verification section rather than deleting it

## Change Guidance for Copilot

- Favor minimal, localized changes that preserve the current architecture
- Fix issues at the service or manager layer rather than patching symptoms in views
- When editing `DeviceManager`, `AppDiscoveryService`, or `DeviceAppMonitoringService`, preserve the current responsibilities and avoid moving unrelated logic across layers
- Do not remove protocol seams used for tests
- Do not replace Combine-based flows with a different state management approach unless the change is explicitly requested
- Document public-facing APIs and non-obvious behavior when introducing new abstractions