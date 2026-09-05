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
- **Two menu bar surfaces**: the searchable `.menuBarExtraStyle(.window)` panel (the default) and the original `NSMenu`, selected by the `LEGACY_MENU_BAR` compilation condition — see `MenuBarPresentation`. It has to be compile-time: `SceneBuilder` has no conditionals, the two `MenuBarExtra` styles are different types, and declaring both scenes puts **two** icons in the menu bar (`isInserted:` does not prevent the status item being created). Both surfaces are driven by the same view models, so behaviour lives in one place; only the rendering differs
- **Why a panel at all**: a real `NSMenu` cannot filter its items as the user types, and no API makes it do so
- **`MenuNode` / `MenuTreeBuilder`**: the panel's menu is described as a **tree of data** — actions, submenus, section headers, informational rows, dividers — built from the view models and `Settings`. The panel renders that tree; selection, drill-down and search filtering all operate on it, so none of them is reimplemented per view. Node identity is derived from the thing a row represents (device UDID, bundle identifier) and never from an array index, so a device refresh cannot make the selection jump. Add menu entries by extending the builder, not by adding views
- **`MenuPanelViewModel`**: drill-down path and keyboard state (selection, arrow movement, the two-step guard on destructive rows). The path is kept as identifiers resolved against a freshly built tree on every render, which is what lets FSEvents-driven changes land in an open panel
- **`MenuSearchService`** (behind `MenuSearching`) + **`MenuSearchViewModel`**: type-to-filter search. The index is built from devices, recent apps and `Settings.visiblePlatforms`, follows those publishers, and never touches the filesystem; strings are normalised once at index time because matching runs per keystroke
- **`MenuBarMenuPresenter`** (behind `MenuBarMenuPresenting`): opens and closes the panel by clicking the status item's button, found by class name in `NSApp.windows`. The one place that depends on `MenuBarExtra` internals — keep it isolated there
- **`DeviceManager`**: central coordinator/source of truth for simulator devices, device types, and recent installed apps
- **`AppDiscoveryService`**: scans simulator folders, reads plist metadata (via `CustomPropertyListDecoder`), constructs app and app-group models
- **`DeviceAppMonitoringService`**: main-actor service managing per-device `AppFolderMonitor` instances (built on `FolderMonitor`, which uses FSEvents); updates recent apps when simulator app containers change, debounced 3s; an app only counts as updated when its `contentModifiedAt` moved forward
- **`Device`**: reference type with mutable `@Published` state for apps/app groups — do not convert to a value type without a clear architectural reason
- **`SimulatorPaths`**: centralizes CoreSimulator directory path derivation — reuse instead of re-hardcoding paths
- **`Settings`**: centralizes user preferences via a `UserDefaults` suite; add new prefs here rather than scattering `UserDefaults` access
- App sandbox is intentionally disabled (`com.apple.security.app-sandbox = false` in `SimulatorManager.entitlements`) — required for direct filesystem access to CoreSimulator directories under `~/Library`. Do not re-enable sandboxing.

### Patterns to follow

- Two observation patterns coexist by layer — follow the one that matches where you are:
  - **View models** (`SimulatorManager/ViewModels/`) are `@MainActor @Observable` classes (Swift Observation), held by views with `@State`. Mark injected dependencies and non-UI state `@ObservationIgnored` (see `SimulatorManagerViewModel`)
  - **Model and service layer** (`DeviceManager`, `Device`, `Settings`, `GithubService`, `DeviceAppMonitoringService`) is `ObservableObject` with `@Published` and Combine, consumed by views via `@StateObject`/`@ObservedObject`
- Wherever Combine is used, store subscriptions in `Set<AnyCancellable>` (`@ObservationIgnored` inside an `@Observable` view model) and `.receive(on: DispatchQueue.main)` before assigning observed state
- Keep views thin/presentation-only; discovery, monitoring, reset, and filesystem logic belongs in services/managers
- Container shortcuts come from `AppContainerShortcut` / `AppGroupShortcut`, not from hand-written lists — both surfaces read those enums, so a new shortcut appears in the menu and the panel at once, and a shortcut whose URL cannot be resolved is never offered
- Recent Apps is filtered by `Settings.visiblePlatforms`, like the device-type sections and search. Note `DeviceManager` caps the list at 20 **before** that filter runs, so hidden-platform entries have already consumed slots
- The panel gets nothing for free that `NSMenu` used to supply. Arrow navigation, `↩`, submenu traversal, dismissal and **accessibility labels** are all hand-written — a new row kind needs its own selectability, its VoiceOver label and its keyboard behaviour, or it silently becomes unreachable
- New services used by view models should be defined behind a protocol when they need mocking (see `DeviceManaging`, `DeviceAppMonitoring`), with constructor injection
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
- `MenuBarMenuPresenterTests` runs inside the host app against the **real** status item and panel, so it catches a SwiftUI change that would otherwise leave the shortcut silently doing nothing. It is `.serialized` because those cases share one panel
- Full testing conventions and rationale: [SimulatorManagerTests/README.md](SimulatorManagerTests/README.md)

## Change guidance

- Favor minimal, localized changes that preserve the current architecture; fix issues at the service/manager layer, not by patching views
- Don't remove protocol seams used for tests
- Don't replace the Combine-based flows in the model/service layer with a different state management approach unless explicitly requested
