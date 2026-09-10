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

### Agent skills from Xcode

Xcode 27 ships Apple-authored agent skills and exports them as a Claude Code plugin named
`xcode-integration`. As of 27.0 RC (`27A266a`) there are 15:
- SwiftUI and App Intents specialists
- accessibility (Dynamic Type, sufficient contrast, VoiceOver)
- `translation` / `translation-coordinator`
- `device-interaction`, `modernize-tests`, security auditing and others

Link them into a checkout with:

```bash
./Scripts/link-xcode-skills.sh
```

The script builds a skills-only wrapper at `.claude/skills/xcode-integration/`: Xcode's own
`plugin.json` plus a symlink to Xcode's `skills` folder. Claude Code then loads the skills as
`xcode-integration@skills-dir`, named `xcode-integration:<skill>`. Three facts drive that design:

- **The namespace is required, not cosmetic.** Xcode's String Catalog MCP tools refuse to run until
  the agent has activated `xcode-integration:translation` / `…:translation-coordinator`. Loose
  copies of the same skills in `.claude/skills/<name>/` load unnamespaced and never match. The
  script warns if one is found.
- **The exported plugin's `.mcp.json` is deliberately left out.** It declares an `xcode` MCP
  server; this repo doesn't configure Xcode's MCP tools, and adding them is a separate decision.
- **The links are developer-local and follow the installed Xcode.**
  - `.claude/skills/xcode-integration/` is git-ignored.
  - The export directory is per Xcode build
    (`~/Library/Developer/Xcode/CodingAssistant/ExportedPlugins/<build>/claude`).
  - Re-run the script after every Xcode update and in every new worktree.
  - Never commit copies of the skills: they go stale with the next Xcode release.

## Architecture

Lightweight MVVM with service-based filesystem logic.

- **App entry**: `SimulatorManagerApp` wires shared state and dependencies (`DeviceManager`, `SimulatorResetService`, `Settings`)
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
- Full testing conventions and rationale: [SimulatorManagerTests/README.md](SimulatorManagerTests/README.md)

## Change guidance

- Favor minimal, localized changes that preserve the current architecture; fix issues at the service/manager layer, not by patching views
- Don't remove protocol seams used for tests
- Don't replace the Combine-based flows in the model/service layer with a different state management approach unless explicitly requested
