# Contributing to Simple Simulator Manager

Thanks for taking an interest. Issues and pull requests are both welcome — bug reports and small
fixes just as much as features.

## Requirements

- macOS 15.0 or later
- Xcode with the macOS toolchain

The app is not sandboxed, on purpose: it reads simulator data directly out of
`~/Library/Developer/CoreSimulator`, which the sandbox would block. Please don't re-enable it.

## Building and testing

Scheme `SimulatorManager`, project `SimulatorManager.xcodeproj`:

```bash
xcodebuild -project SimulatorManager.xcodeproj -scheme SimulatorManager build
xcodebuild -project SimulatorManager.xcodeproj -scheme SimulatorManager test
```

A single suite:

```bash
xcodebuild -project SimulatorManager.xcodeproj -scheme SimulatorManager test \
  -only-testing:SimulatorManagerTests/DeviceViewModelTests
```

SwiftFormat and SwiftLint run automatically as build phases, so a normal build formats and lints
your changes. You can also run `swiftformat .` and `swiftlint` directly.

## Workflow

**Start from an issue for anything non-trivial.** It's where the goal and how to verify it get
agreed before code is written, which saves rework. A typo or one-line fix doesn't need one.

A good issue says what should change, what the resulting behaviour must be, how to verify it, and
anything deliberately left out.

**Name your branch after the issue**, using GitHub's own format — `<issue-number>-<slugified-title>`,
lowercase and hyphen separated:

```
49-configurable-global-keyboard-shortcut-to-open-the-menu-bar-menu
```

The easiest way is to let GitHub derive it:

```bash
gh issue develop <number> --base develop
```

**Open pull requests against `develop`**, not `main`, with `Closes #<number>` in the body. Note that
GitHub can't re-point a pull request's head branch after it's opened, so it's worth getting the
branch name right before your first push.

`.github/pull_request_template.md` pre-fills the description. Please fill in how you verified the
change rather than deleting that section, and include a screenshot or short recording for anything
that changes the menu bar UI — the menu can't be reviewed from a diff.

## Conventions

[CLAUDE.md](CLAUDE.md) is the full reference for architecture and conventions. The parts that come
up most in review:

- Two observation patterns coexist **by layer**. View models are `@MainActor @Observable`; the model
  and service layer (`DeviceManager`, `Device`, `Settings`, …) stays `ObservableObject` with
  `@Published` and Combine. Please don't unify them.
- Views stay thin. Discovery, monitoring, reset and filesystem logic belongs in services and
  managers.
- Services that view models depend on sit behind a protocol when they need mocking, injected through
  the initialiser.
- Handle missing files, missing folders and decode failures defensively. Log recoverable problems
  with `os_log` instead of crashing.
- New preferences go through `Settings`; CoreSimulator paths go through `SimulatorPaths`.

## Tests

The project uses [Swift Testing](https://developer.apple.com/documentation/testing) — `@Suite`,
`@Test`, `#expect` — not XCTest. Mocks live in `SimulatorManagerTests/Mocks`, factories in
`SimulatorManagerTests/Helpers`.

Combine-driven tests need to let values propagate before asserting. Conventions and the reasoning
behind them are in [SimulatorManagerTests/README.md](SimulatorManagerTests/README.md).

New behaviour should come with tests. If something is genuinely hard to test, say so in the pull
request rather than skipping it silently.

## Reporting bugs

Please include your macOS and Xcode versions, what you expected, and what happened instead. For
simulator-specific problems, the output of `xcrun simctl list devices --json` is often the fastest
way to see what the app was looking at.

## Licence

By contributing you agree that your contributions are licensed under the [MIT Licence](LICENSE),
the same as the rest of the project.
