# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository

- Product: macOS `MenuBarExtra` SwiftUI app for inspecting and managing apps installed in local Apple simulators
- Target: macOS 14+ (some targets require 15.0, check `MACOSX_DEPLOYMENT_TARGET` per target)
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
- **`SimulatorPaths`**: centralizes CoreSimulator directory path derivation — reuse instead of re-hardcoding paths
- **`Settings`**: centralizes user preferences via a `UserDefaults` suite; add new prefs here rather than scattering `UserDefaults` access
- App sandbox is intentionally disabled (`com.apple.security.app-sandbox = false` in `SimulatorManager.entitlements`) — required for direct filesystem access to CoreSimulator directories under `~/Library`. Do not re-enable sandboxing.

### Patterns to follow

- View models are `ObservableObject` with `@Published` properties and Combine; store subscriptions in `Set<AnyCancellable>`, receive on main queue before assigning published state
- Keep views thin/presentation-only; discovery, monitoring, reset, and filesystem logic belongs in services/managers
- New services used by view models should be defined behind a protocol when they need mocking (see `DeviceManaging`, `DeviceAppMonitoring`), with constructor injection
- Handle missing files/folders/decode failures defensively; log recoverable failures with `os_log` instead of crashing; filter out `.DS_Store` and similar noise
- Recent-apps behavior in `DeviceManager` must stay: dedupe by bundle identifier + device UDID, sort by most recent timestamp, cap list size; when comparing app changes, diff bundle identifiers and treat an app as updated only if its `contentModifiedAt` moved forward
- AppKit usage is fine for Finder/system integration; don't leak iOS-only assumptions into shared code
- Prefer Combine/`ObservableObject` over the Observation macros unless the codebase is intentionally migrated

## Testing

- Uses **Swift Testing** (`@Suite`, `@Test`, `#expect`), not XCTest
- Mocks live in `SimulatorManagerTests/Mocks`, test data factories in `SimulatorManagerTests/Helpers/TestDataHelpers`
- Combine-driven tests need to await async propagation (e.g. `try? await Task.sleep(...)`) before asserting on `@Published` state
- When changing `DeviceManager` or view models, cover sorting, deduplication, and edge cases
- Full testing conventions and rationale: [SimulatorManagerTests/README.md](SimulatorManagerTests/README.md)

## Change guidance

- Favor minimal, localized changes that preserve the current architecture; fix issues at the service/manager layer, not by patching views
- Don't remove protocol seams used for tests
- Don't replace Combine-based flows with a different state management approach unless explicitly requested
