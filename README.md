<div align="center">

<img width="128" height="128" alt="Simple Simulator Manager app icon" src="https://github.com/user-attachments/assets/750cc48f-0d71-49d2-bbb0-28b9a1d9d2ae" />

# Simple Simulator Manager

**A macOS menu bar app that gets you straight to the files inside your Xcode simulators.**

Open any simulator app's data container, `.app` package, Documents folder, `UserDefaults` or shared
App Group in Finder — without hunting through CoreSimulator UUIDs. Then clean up the dead simulators
quietly eating your disk.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat)](LICENSE)
[![Platform](https://img.shields.io/badge/macOS-15.0%2B-lightgrey?style=flat&logo=apple)](#requirements)
[![In development since October 2023](https://img.shields.io/badge/in%20development%20since-October%202023-6a737d?style=flat)](#history)
[![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-db61a2?style=flat&logo=githubsponsors&logoColor=white)](https://github.com/sponsors/Heckscheibe)
[![Swift for Swifts](https://img.shields.io/badge/SWIFT-FOR%20SWIFTS-F6AF41?style=flat&labelColor=476B64&logo=swift&logoColor=F6AF41)](https://swiftforswifts.org)

</div>

```bash
brew install --cask heckscheibe/tap/simple-simulator-manager
```

<img width="380" alt="The Simple Simulator Manager menu, showing recent apps with an app submenu open, the simulator list grouped by device, the section visibility toggles, Settings… and the cleanup and reset actions" src="Screenshots/Screenshot 2.jpeg" />

---

## The problem

Inspecting a simulator app's database, cache or preferences means finding it first:

```
~/Library/Developer/CoreSimulator/Devices/<device-UUID>/data/Containers/Data/Application/<app-UUID>/
```

Both UUIDs are opaque, and the app one changes on reinstall. Xcode gives you no UI for this, so you
end up in Terminal or clicking through Finder every time.

Simple Simulator Manager puts it two clicks from the menu bar.

## Features

**Reach any app's files**
- Every installed simulator, grouped by device type and OS version
- Per app: **App Folder**, **Documents Folder**, **App Package** and **User Defaults**
- Per app group: **Group Folder** and **Group UserDefaults**
- **Simulator Folder** for the device's own directory

**Recent apps**
- The most recently installed and updated apps across *all* simulators, with device context
- Updates live as you build and install — no manual refresh
- Can be hidden if you don't want it

**Snapshots for database migration testing**
- **Save Snapshot to Folder** copies an app's data — everything, only its database (SQLite, Core
  Data, SwiftData, GRDB, Realm), only its UserDefaults, or both — so you keep exactly what an older
  build left behind
- Built for testing migrations: save the old build's database before installing the new build, and
  the migrated one before trying a downgrade
- With the [MCP server](#use-with-ai-agents-mcp), an agent captures, restores and diffs the data
  itself, so it can run a migration, a relaunch or a downgrade again and again from the same data

**Cleanup**
- Detects unavailable, orphaned and otherwise invalid simulators
- Shows the deletion reason, disk usage and last boot time before you remove anything
- Delete individually, grouped by OS version, or all at once

**Reset**
- Erase a single simulator from its own menu
- Bulk **Reset All Simulators** with progress and a confirmation step

**Keyboard and settings**
- A global shortcut opens the menu from anywhere — **⌃⌥⌘S** by default
- Once the menu is open, the arrow keys navigate it, Return activates and typing jumps to an entry
- **Settings…** opens a window to rebind or clear the shortcut, and to show or hide Recent Apps and
  the individual platform sections

**Other**
- Only platforms you actually have simulators for appear
- Update indicator when a new release is available

## Requirements

- macOS 15.0 or later
- Xcode with at least one installed simulator runtime

> [!NOTE]
> visionOS simulators appear in the list and can be managed, but app discovery inside them is not
> supported — the platform stores app containers differently.

## Installation

Homebrew:

```bash
brew install --cask heckscheibe/tap/simple-simulator-manager
```

Update later:

```bash
brew upgrade --cask simple-simulator-manager
```

Or download the latest notarized build from [Releases](https://github.com/Heckscheibe/SimpleSimulatorManager/releases)
and move `Simulator Manager.app` to your Applications folder.

## Usage

The app lives in the menu bar — there is no main window.

1. Click the menu bar icon — or press **⌃⌥⌘S** from anywhere — to see your simulators, grouped by
   platform and device.
2. Hover a simulator for **Simulator Folder**, **Apps**, **AppGroups** and **Erase Simulator**.
3. Hover an app for **App Folder**, **Documents Folder**, **App Package** and **User Defaults**. Any
   of them opens directly in Finder — point a tool like [DB Browser for SQLite](https://sqlitebrowser.org/)
   at the result.
4. **Recent Apps** at the top of the menu tracks what you've most recently installed or rebuilt.
5. **Cleanup Simulators** scans for invalid simulators and shows why each one qualifies, plus its
   disk usage, before you delete it.
6. **Settings…** — or ⌘, while the menu is open — opens a window where you can record a different
   global shortcut, clear it if you would rather not have one, or reset it to the default, and
   choose which sections the menu shows.

<img width="860" alt="The cleanup view listing deletable simulators grouped by OS version, with a detail popover showing the deletion reason, platform, OS, disk usage and UDID" src="Screenshots/Screenshot 1.jpeg" />

<img width="460" alt="The Settings window, showing the Global Shortcut section with the recorder set to ⌃⌥⌘S alongside Clear and Reset buttons, and the Menu Contents section with toggles for Recent Apps and each platform" src="Screenshots/Screenshot 3.jpeg" />

## Use with AI agents (MCP)

`simple-simulator-mcp` is a [Model Context Protocol](https://modelcontextprotocol.io) server that
gives coding agents such as Claude Code, VS Code Copilot, Codex or Cursor the same knowledge the
menu has: simulators, installed apps, their data, bundle and app-group containers, recent installs
and cleanup candidates. Its main job beyond that is **database migration testing**: it snapshots,
diffs and restores an app's data, so an agent can run a migration again and again from exactly the
same old-build data (see [Testing a migration](#testing-a-migration)). It runs over stdio as a
subprocess of the agent, works whether or not the menu bar app is running, and opens no network
port. Tools take UDIDs, bundle identifiers and other identifiers — never file paths.

It is read-only by default, plus `shutdown_all_simulators`, which loses no data. Three launch
flags, set per agent in its MCP config, opt into more:

- `--allow-user-defaults` enables `read_user_defaults` (UserDefaults can hold tokens or personal
  data), and adds UserDefaults values to `diff_snapshot`
- `--allow-destructive` enables `erase_device`, `erase_all_simulators` and `delete_cleanup_candidate`
- `--allow-snapshots` enables `capture_snapshot`, `diff_snapshot`, `restore_snapshot` and
  `delete_snapshot`, without unlocking the destructive tools

| Tool | Available |
|---|---|
| `list_devices`, `list_apps`, `find_app`, `get_app_containers`, `list_app_groups`, `list_recent_apps`, `list_cleanup_candidates` | always (read-only) |
| `shutdown_all_simulators` | always |
| `read_user_defaults` | with `--allow-user-defaults` |
| `erase_device`, `erase_all_simulators`, `delete_cleanup_candidate` | with `--allow-destructive` |
| `list_snapshots` | always (read-only) |
| `capture_snapshot`, `diff_snapshot`, `restore_snapshot`, `delete_snapshot` | with `--allow-snapshots` |

> **Privacy:** `read_user_defaults` hands an app's preferences to the agent, and from there possibly
> to a model provider. UserDefaults often hold tokens, user identifiers or other personal data, so
> enable it only for agents you trust with that data. Snapshots copy whatever the app stored,
> unencrypted, to `~/Library/Application Support/SimulatorManager/Snapshots`; the agent only sees
> file names and sizes, and defaults values only with `--allow-user-defaults`.

### Testing a migration

This is what the snapshot tools are for. With `--allow-snapshots`, an agent can freeze the database
an old build left behind and run the new build against exactly that data as often as it takes:

```
find_app → capture_snapshot (old build, contents: "databases")
  → build and install the new build, launch it (xcodebuild / simctl — not this server)
  → diff_snapshot against_live (what did the migration change?)
  → restore_snapshot (accept_warnings: true) → diff_snapshot against_live (old data back?) → repeat
```

The same tools cover the rest of an upgrade and downgrade check:

| Scenario | How |
|---|---|
| Migrate the old data with the new build, repeatedly | restore the old-build snapshot, launch the new build, read the result, repeat |
| Relaunch the new build on data it already migrated | launch it again without restoring; `diff_snapshot` against a snapshot of the migrated data |
| Downgrade: the old build on migrated data | capture the migrated data, reinstall the old build and launch it; `diff_snapshot` shows whether it touched the database |
| Back to the new build after a downgrade | reinstall the new build and launch it; restore the migrated snapshot to start over |

`capture_snapshot` terminates the app first so the database and its `-wal` are copied in a
consistent state. `restore_snapshot` terminates it too, takes a safety snapshot whose id it returns,
and with `contents: "databases"` or `"userDefaults"` replaces only those files, so logs and other
files in the container keep what every launch wrote. A restore onto another app or OS version
returns warnings and writes nothing until `accept_warnings: true` — expected when testing a
migration. Snapshots take disk space: `list_snapshots` reports `byteSize`, `delete_snapshot` removes
one.

### Setup

The server ships inside the app at
`/Applications/Simulator Manager.app/Contents/Helpers/simple-simulator-mcp`, signed and notarized
with it. The Homebrew cask also puts it on your `PATH` as `simple-simulator-mcp`.

The easiest way to set it up is **Settings → Agent Integration (MCP)**. Choose your agent, tick
the flags you want, and copy the ready-made config. To set it up by hand instead:

**Claude Code**

```bash
claude mcp add --scope user simple-simulator -- "/Applications/Simulator Manager.app/Contents/Helpers/simple-simulator-mcp"
```

**VS Code (GitHub Copilot)**: add to `.vscode/mcp.json`, or to your user configuration via
*MCP: Open User Configuration*. The tools then show up in Copilot Chat's Agent mode.

```json
{
  "servers": {
    "simple-simulator": {
      "type": "stdio",
      "command": "/Applications/Simulator Manager.app/Contents/Helpers/simple-simulator-mcp",
      "args": []
    }
  }
}
```

**Codex**: add to `~/.codex/config.toml`:

```toml
[mcp_servers.simple-simulator]
command = "/Applications/Simulator Manager.app/Contents/Helpers/simple-simulator-mcp"
args = []
```

**Cursor, Claude Desktop and other clients**: add to the client's `mcpServers` config, for example
`~/.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "simple-simulator": {
      "command": "/Applications/Simulator Manager.app/Contents/Helpers/simple-simulator-mcp",
      "args": []
    }
  }
}
```

Put `--allow-user-defaults`, `--allow-destructive` and/or `--allow-snapshots` into `args` (or after
the path, for Claude Code) to opt in.

To run it from a checkout instead, build it with SwiftPM:

```bash
swift build -c release --package-path Packages/SimulatorCore --product simple-simulator-mcp
```

## Security and privacy

Simple Simulator Manager runs with the [App Sandbox](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.app-sandbox)
**disabled**. It has to: reading the CoreSimulator directories under `~/Library` is the entire point
of the app, and a sandboxed app cannot do it.

That is a powerful entitlement, and it's why this app can never ship on the Mac App Store. It is
also why the full source is in this repository. With an entitlement like this, being auditable is
the only reasonable basis for trust — you can read exactly what it touches.

The global shortcut is registered through Carbon's `RegisterEventHotKey`, which the system resolves
before the keystroke reaches any app. It is not a keyboard monitor: the app never sees your other
keystrokes and needs no Accessibility permission.

The app works entirely offline. The only network request it makes is a check against the GitHub
Releases API for a newer version. Nothing is collected, and nothing is sent anywhere.

## Building from source

Requires Xcode. SwiftFormat and SwiftLint run automatically as build phases.

```bash
xcodebuild -project SimulatorManager.xcodeproj -scheme SimulatorManager build
```

Run the tests ([Swift Testing](https://developer.apple.com/xcode/swift-testing/)):

```bash
xcodebuild -project SimulatorManager.xcodeproj -scheme SimulatorManager test
```

Signed and notarized release builds go through fastlane and need a `.env` with signing secrets —
see [FASTLANE_README.md](FASTLANE_README.md).

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for how to build, test
and submit changes; testing conventions are documented in
[SimulatorManagerTests/README.md](SimulatorManagerTests/README.md).

## License

[MIT](LICENSE) © 2024–2026 Nicolas Hiller

## History

Simple Simulator Manager has been in development since **October 2023**. It exists because
[XSimulatorMngr](https://github.com/wcb133/XSimulatorMngr) — the tool I relied on for exactly this —
was discontinued, and nothing replaced it. I used it for years and it helped me a lot.

It was written by hand, before AI coding agents existed, and it has grown through daily use rather
than in one push: the cleanup view exists because I ran out of disk space, and the live recent-apps
list exists because I got tired of re-navigating after every rebuild.

> [!NOTE]
> The commit history in this repository begins in August 2025. Development started earlier, as the
> `Created by` headers in the source files show.

> Simple Simulator Manager makes local testing faster — but still test on real devices before you
> ship. 😉
