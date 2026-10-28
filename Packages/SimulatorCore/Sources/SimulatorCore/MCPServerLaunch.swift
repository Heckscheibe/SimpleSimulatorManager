//
//  MCPServerLaunch.swift
//  SimulatorCore
//

import Foundation

/// How agents launch the `simple-simulator-mcp` server: its executable name, its opt-in flags and
/// where the app bundle carries it.
///
/// Lives here rather than in `SimulatorMCPServer` because the app builds MCP client configs from it
/// and must not link the MCP SDK.
public enum MCPServerLaunch {
    public static let executableName = "simple-simulator-mcp"

    /// Enables reading UserDefaults content, which can hold tokens or personal data.
    public static let allowUserDefaultsFlag = "--allow-user-defaults"
    /// Enables erasing simulators and deleting cleanup candidates.
    public static let allowDestructiveFlag = "--allow-destructive"
    /// Enables capturing, diffing, restoring and deleting app snapshots.
    public static let allowSnapshotsFlag = "--allow-snapshots"

    /// The embedded executable, relative to the app bundle.
    public static let bundleRelativePath = "Contents/Helpers/\(executableName)"

    /// The launch arguments for the given opt-ins, in a stable order.
    public static func arguments(allowUserDefaults: Bool, allowDestructive: Bool, allowSnapshots: Bool = false) -> [String] {
        (allowUserDefaults ? [allowUserDefaultsFlag] : [])
            + (allowDestructive ? [allowDestructiveFlag] : [])
            + (allowSnapshots ? [allowSnapshotsFlag] : [])
    }
}
