# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository

- Product: macOS `MenuBarExtra` SwiftUI app for inspecting and managing apps installed in local Apple simulators
- Target: **macOS 15.0+** — the app target and `LSMinimumSystemVersion` are both 15.0; the project-level `MACOSX_DEPLOYMENT_TARGET` of 14.0 is only an inherited default the targets override, so don't quote it as the requirement
- Not an iOS app; visionOS simulators appear in the UI but app discovery differs by platform

## Commands

Build and test via Xcode/xcodebuild (scheme: `SimulatorManager`, project: `SimulatorManager.xcodeproj`):

```bash
# Build
xcodebuild -project SimulatorManager.xcodeproj -scheme SimulatorManager build

# Run all tests
xcodebuild -project SimulatorManager.xcodeproj -scheme SimulatorManager test

# Run a single test (Swift Testing framework)
xcodebuild -project SimulatorManager.xcodeproj -scheme SimulatorManager test \
  -only-testing:SimulatorManagerTests/DeviceViewModelTests
```

Formatting/linting run automatically as Xcode build phases (SwiftFormat then SwiftLint), but can be run manually:

```bash
swiftformat .
swiftlint
```

Release build (signed, notarized, requires `.env` with signing/notarization secrets — see [FASTLANE_README.md](FASTLANE_README.md)):

```bash
./build.sh          # wraps `bundle exec fastlane release`
bundle exec fastlane build    # unsigned debug build only
```

## Architecture

Lightweight MVVM with service-based filesystem logic.

- **App entry**: `SimulatorManagerApp` wires shared state and dependencies (`DeviceManager`, `SimulatorResetService`, `Settings`)
- **`DeviceManager`**: central coordinator/source of truth for simulator devices, device types, and recent installed apps
- **`AppDiscoveryService`**: scans simulator folders, reads plist metadata (via `CustomPropertyListDecoder`), constructs app and app-group models
- **`DeviceAppMonitoringService`**: main-actor service managing per-device `AppFolderMonitor` instances (built on `FolderMonitor`, which uses FSEvents); updates recent apps when simulator app containers change, debounced 3s; an app only counts as updated when its `contentModifiedAt` moved forward
- **`Device`**: reference type with mutable `@Published` state for apps/app groups — do not convert to a value type without a clear architectural reason
- **`AppSnapshotService`**: captures, restores and diffs an app's containers behind `AppSnapshotting`. The layout of `~/Library/Application Support/SimulatorManager/Snapshots` belongs to `AppSnapshotStore`, the filesystem walk and copy to `SnapshotContainerFiles`, and comparison to `SnapshotComparison` / `SnapshotDefaultsDiffer` — keep those seams. A restore terminates the app through `SimulatorAppActionServing` and always takes a safety snapshot first; version and OS mismatches are *returned* as warnings for the caller to confirm, never decided in the service
- **`SimulatorPaths`**: centralizes CoreSimulator directory path derivation — reuse instead of re-hardcoding paths
- **`Settings`**: centralizes user preferences via a `UserDefaults` suite; add new prefs here rather than scattering `UserDefaults` access
- App sandbox is intentionally disabled (`com.apple.security.app-sandbox = false` in `SimulatorManager.entitlements`) — required for direct filesystem access to CoreSimulator directories under `~/Library`. Do not re-enable sandboxing.

### Patterns to follow

- Two observation patterns coexist by layer — follow the one that matches where you are:
  - **View models** (`SimulatorManager/ViewModels/`) are `@MainActor @Observable` classes (Swift Observation), held by views with `@State`. Mark injected dependencies and non-UI state `@ObservationIgnored` (see `SimulatorManagerViewModel`)
  - **Model and service layer** (`DeviceManager`, `Device`, `Settings`, `GithubService`, `DeviceAppMonitoringService`) is `ObservableObject` with `@Published` and Combine, consumed by views via `@StateObject`/`@ObservedObject`
- Wherever Combine is used, store subscriptions in `Set<AnyCancellable>` (`@ObservationIgnored` inside an `@Observable` view model) and `.receive(on: DispatchQueue.main)` before assigning observed state
- Keep views thin/presentation-only; discovery, monitoring, reset, and filesystem logic belongs in services/managers
- New services used by view models should be defined behind a protocol when they need mocking (see `DeviceManaging`, `DeviceAppMonitoring`), with constructor injection
- Blocking filesystem or `simctl` work goes on a dedicated `DispatchQueue`, never `Task.detached` — that shares the Swift concurrency cooperative pool, and a multi-second directory walk there starves unrelated async work (see `SimulatorCleanupService.workQueue`, `AppSnapshotService.workQueue`)
- Never derive a container path a second time: reuse what `AppDiscoveryService` found, and the app/app-group association rule in `AppGroup.isAssociated(with:)`
- Handle missing files/folders/decode failures defensively; log recoverable failures with `os_log` instead of crashing; filter out `.DS_Store` and similar noise
- Recent-apps behavior in `DeviceManager` must stay: dedupe by bundle identifier + device UDID, sort by most recent timestamp, cap list size; when comparing app changes, diff bundle identifiers and treat an app as updated only if its `contentModifiedAt` moved forward
- AppKit usage is fine for Finder/system integration; don't leak iOS-only assumptions into shared code
- Preserve the layer split above rather than unifying it: don't convert a view model to `ObservableObject`, and don't convert the model/service layer to `@Observable`, without a clear architectural reason

## Issue, branch and worktree workflow

**Every feature branch and every git worktree must be named after the GitHub issue it implements.** This is mandatory, not a preference.

Use GitHub's own issue-branch format — `<issue-number>-<slugified-issue-title>`, lowercase, hyphen separated:

```
49-configurable-global-keyboard-shortcut-to-open-the-menu-bar-menu
50-epic-type-to-filter-search-in-the-menu-bar-menu
```

This matches the branches GitHub generates from "Create a branch for this issue" and the existing convention in this repo (`32-add-advanced-simulator-utilities`, `33-add-per-device-simulator-actions`).

Rules:

- Work on a feature is **never** committed directly to `develop` — branch first
- A worktree uses the **same name** as its branch; do not use generated or random names
- If no issue exists for the work, **create the issue first**, then branch from its number
- The issue is the spec: it must carry everything needed to **implement and verify** the change — context, the required behaviour for each part, knock-on effects elsewhere in the app, an explicit verification checklist, and what is deliberately out of scope
- Maintainers additionally add the issue to the project board and set its Status:
  `gh project item-add 1 --owner Heckscheibe --url <issue-url>`. Outside contributors skip this — the board is not writable by them
- Prefer creating the branch with `gh issue develop <number> --base develop`, which derives the name automatically and links branch to issue
- Some older branches use a `feature/` prefix (`feature/27-add-confirmation-dialogue-…`); for new work use the bare `<number>-<slug>` form
- Exceptions, which keep their tool-generated names: `dependabot/*` and `release/*`

Pull requests:

- Open against `develop`, never `main`, with `Closes #<number>` in the body so the issue and board item close with the merge
- A PR's head branch **cannot be changed after it is opened** — a wrongly named branch means closing the PR and reopening it from a correctly named one, so get the branch right before the first push
- `.github/pull_request_template.md` pre-fills the description; fill in the verification section rather than deleting it

## Testing

- Uses **Swift Testing** (`@Suite`, `@Test`, `#expect`), not XCTest
- Mocks live in `SimulatorManagerTests/Mocks`, test data factories in `SimulatorManagerTests/Helpers/TestDataHelpers`
- Combine-driven tests need to await async propagation (e.g. `try? await Task.sleep(...)`) before asserting on `@Published` state
- When changing `DeviceManager` or view models, cover sorting, deduplication, and edge cases
- Full testing conventions and rationale: [SimulatorManagerTests/README.md](SimulatorManagerTests/README.md)

## Change guidance

- Favor minimal, localized changes that preserve the current architecture; fix issues at the service/manager layer, not by patching views
- Don't remove protocol seams used for tests
- Don't replace the Combine-based flows in the model/service layer with a different state management approach unless explicitly requested
