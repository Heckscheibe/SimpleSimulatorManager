//
//  SimulatorTool.swift
//  SimulatorMCPServer
//

import Foundation
import MCP
import SimulatorCore

/// The launch flag a tool needs before it is listed or callable.
public enum ToolGate: Sendable, Equatable {
    case alwaysAvailable
    case userDefaults
    case destructive
    case snapshots

    public var flag: String? {
        switch self {
        case .alwaysAvailable:
            nil
        case .userDefaults:
            ServerOptions.allowUserDefaultsFlag
        case .destructive:
            ServerOptions.allowDestructiveFlag
        case .snapshots:
            ServerOptions.allowSnapshotsFlag
        }
    }

    func isOpen(for options: ServerOptions) -> Bool {
        switch self {
        case .alwaysAvailable:
            true
        case .userDefaults:
            options.allowUserDefaults
        case .destructive:
            options.allowDestructive
        case .snapshots:
            options.allowSnapshots
        }
    }
}

/// Every tool the server knows, gated or not. Tools take identifiers only — never paths — so no
/// tool can be pointed at an arbitrary file.
public enum SimulatorTool: String, CaseIterable, Sendable {
    case listDevices = "list_devices"
    case listApps = "list_apps"
    case findApp = "find_app"
    case getAppContainers = "get_app_containers"
    case listAppGroups = "list_app_groups"
    case listRecentApps = "list_recent_apps"
    case listCleanupCandidates = "list_cleanup_candidates"
    case shutdownAllSimulators = "shutdown_all_simulators"
    case readUserDefaults = "read_user_defaults"
    case eraseDevice = "erase_device"
    case eraseAllSimulators = "erase_all_simulators"
    case deleteCleanupCandidate = "delete_cleanup_candidate"
    case listSnapshots = "list_snapshots"
    case captureSnapshot = "capture_snapshot"
    case diffSnapshot = "diff_snapshot"
    case restoreSnapshot = "restore_snapshot"
    case deleteSnapshot = "delete_snapshot"

    enum Argument {
        static let platform = "platform"
        static let state = "state"
        static let udid = "udid"
        static let bundleId = "bundle_id"
        static let appGroupId = "app_group_id"
        static let domain = "domain"
        static let limit = "limit"
        static let id = "id"
        static let snapshotId = "snapshot_id"
        static let label = "label"
        static let contents = "contents"
        static let includeCaches = "include_caches"
        static let terminateApp = "terminate_app"
        static let againstSnapshotId = "against_snapshot_id"
        static let againstLive = "against_live"
        static let acceptWarnings = "accept_warnings"
    }

    /// The most file changes `diff_snapshot` lists unless told otherwise.
    static let defaultDiffLimit = 500

    public var gate: ToolGate {
        switch self {
        case .listDevices, .listApps, .findApp, .getAppContainers, .listAppGroups, .listRecentApps,
             .listCleanupCandidates, .shutdownAllSimulators, .listSnapshots:
            .alwaysAvailable
        case .readUserDefaults:
            .userDefaults
        case .eraseDevice, .eraseAllSimulators, .deleteCleanupCandidate:
            .destructive
        case .captureSnapshot, .diffSnapshot, .restoreSnapshot, .deleteSnapshot:
            .snapshots
        }
    }

    var argumentNames: Set<String> {
        guard let properties = inputSchema.objectValue?["properties"]?.objectValue else {
            return []
        }

        return Set(properties.keys)
    }

    public var definition: Tool {
        Tool(name: rawValue, title: annotations.title, description: description, inputSchema: inputSchema, annotations: annotations)
    }
}

// MARK: - Definitions

private extension SimulatorTool {
    // swiftlint:disable line_length
    var description: String {
        switch self {
        case .listDevices:
            "Lists the local Apple simulators (iOS, iPadOS, watchOS, tvOS, visionOS) with UDID, name, platform, OS version, state, last boot date and device folder. Optionally filtered by platform or state."
        case .listApps:
            "Lists the apps installed on one simulator: bundle identifier, name, iOS or watchOS, when its content last changed and the UserDefaults domains it wrote."
        case .findApp:
            "Finds every simulator that has the app with the given bundle identifier installed."
        case .getAppContainers:
            "Returns the absolute folder paths of an app on one simulator: data container (sandbox root holding Documents, Library and tmp), bundle container, .app bundle, Library/Preferences, plus its app groups' shared containers."
        case .listAppGroups:
            "Lists the app groups on one simulator with their shared container folder and UserDefaults domains."
        case .listRecentApps:
            "Lists the most recently installed or updated apps across all simulators, newest first, one entry per app and simulator — the same list the menu bar app shows."
        case .listCleanupCandidates:
            "Lists simulators and simulator folders that can be cleaned up (missing runtime or device type, unavailable, orphaned or unreadable), with reasons and disk usage. Each id can be passed to delete_cleanup_candidate."
        case .shutdownAllSimulators:
            "Shuts down every running simulator. No data is lost."
        case .readUserDefaults:
            "Returns the UserDefaults an app or app group wrote, as JSON keyed by defaults domain — the same document as the menu's \"Copy UserDefaults as JSON\". Pass exactly one of bundle_id or app_group_id. May contain tokens or personal data."
        case .eraseDevice:
            "Shuts down one simulator and erases all its content and settings. Cannot be undone."
        case .eraseAllSimulators:
            "Shuts down every simulator and erases all their content and settings. Cannot be undone."
        case .deleteCleanupCandidate:
            "Deletes one cleanup candidate by the id list_cleanup_candidates returned: simulators are deleted with simctl, leftover folders are moved to the Trash. Only candidates that still qualify are deleted."
        case .listSnapshots:
            "Lists app snapshots, newest first: id, app, device, label, what they hold, byteSize and whether a restore took it as an undo point. Metadata only, never their contents. Snapshots use disk space until deleted with delete_snapshot."
        case .captureSnapshot:
            "Captures an app's data container and app group containers on one simulator, so the state can be diffed against or restored later — e.g. to test a database migration repeatedly from the same old-build data. Terminates the app on the device before copying, so open databases are captured consistently. Pass terminate_app: false to keep it running, at the risk of capturing a database mid-write. contents limits it to databases (SQLite, Core Data, SwiftData, GRDB, Realm) and/or UserDefaults. The copy holds whatever the app stored, tokens and personal data included, unencrypted in Application Support; remove it with delete_snapshot."
        case .diffSnapshot:
            "Compares a snapshot with another snapshot (against_snapshot_id) or with the app as installed now (against_live). Lists added, removed and modified files by path and size, and changed UserDefaults keys; file contents are never returned, and UserDefaults values only when the server runs with --allow-user-defaults. Only what both sides hold is compared. Database files show up as modified files."
        case .restoreSnapshot:
            "Puts a snapshot back: terminates the app first, then replaces the files the snapshot holds — the whole containers for an everything snapshot, only the databases and/or UserDefaults for a narrower one. Files the snapshot does not cover are left alone. A safety snapshot is taken first; its id is returned so the restore can be undone. If the snapshot was taken from another app or OS version, nothing is written and the warnings are returned; pass accept_warnings: true to restore anyway, as migration testing usually needs."
        case .deleteSnapshot:
            "Deletes one snapshot from disk by id. Cannot be undone."
        }
    }

    var inputSchema: Value {
        switch self {
        case .listDevices:
            Self.schema([
                Argument.platform: Self.stringProperty("Only simulators of this platform.", choices: SimulatorPlatform.allIdentifiers),
                Argument.state: Self.stringProperty("Only simulators in this state.", choices: DeviceState.allIdentifiers)
            ])
        case .listApps, .listAppGroups:
            Self.schema([Argument.udid: Self.udidProperty], required: [Argument.udid])
        case .findApp:
            Self.schema([Argument.bundleId: Self.bundleIdProperty], required: [Argument.bundleId])
        case .getAppContainers:
            Self.schema([Argument.udid: Self.udidProperty, Argument.bundleId: Self.bundleIdProperty],
                        required: [Argument.udid, Argument.bundleId])
        case .listRecentApps:
            Self.schema([
                Argument.limit: .object([
                    "type": "integer",
                    "minimum": .int(1),
                    "maximum": .int(RecentApps.maxCount),
                    "description": .string("Maximum number of apps to return, 1 to \(RecentApps.maxCount). Defaults to \(RecentApps.maxCount).")
                ])
            ])
        case .listCleanupCandidates, .shutdownAllSimulators, .eraseAllSimulators:
            Self.schema()
        case .readUserDefaults:
            Self.schema([
                Argument.udid: Self.udidProperty,
                Argument.bundleId: Self.stringProperty(
                    "Bundle identifier of the app whose UserDefaults to read. Mutually exclusive with app_group_id."
                ),
                Argument.appGroupId: Self.stringProperty(
                    "Identifier of the app group whose UserDefaults to read, e.g. group.com.example.app. Mutually exclusive with bundle_id."
                ),
                Argument.domain: Self.stringProperty(
                    "A single defaults domain to read. Defaults to every domain the app or group wrote, without system domains."
                )
            ], required: [Argument.udid])
        case .eraseDevice:
            Self.schema([Argument.udid: Self.udidProperty], required: [Argument.udid])
        case .deleteCleanupCandidate:
            Self.schema([Argument.id: Self.stringProperty("A cleanup candidate id from list_cleanup_candidates.")], required: [Argument.id])
        case .listSnapshots:
            Self.schema([Argument.bundleId: Self.stringProperty("Only snapshots of the app with this bundle identifier.")])
        case .captureSnapshot:
            Self.schema([
                Argument.bundleId: Self.bundleIdProperty,
                Argument.udid: Self.udidProperty,
                Argument.label: Self.stringProperty("A name for the snapshot. Defaults to device, OS, app and time."),
                Argument.contents: Self.stringProperty(
                    "What to capture. everything (default) is the whole containers; databases is SQLite and Realm files with their -wal, -shm and Core Data external storage; userDefaults is the preference plists.",
                    choices: SnapshotContents.identifiers
                ),
                Argument.includeCaches: Self.booleanProperty("Also capture Library/Caches and tmp. Defaults to false."),
                Argument.terminateApp: Self.booleanProperty(
                    "Terminate the app on the device before copying, so open databases are captured consistently. Defaults to true; false keeps it running, at the risk of capturing a database mid-write."
                )
            ], required: [Argument.bundleId, Argument.udid])
        case .diffSnapshot:
            Self.schema([
                Argument.snapshotId: Self.snapshotIdProperty,
                Argument.againstSnapshotId: Self.stringProperty("Compare with this snapshot. Mutually exclusive with against_live."),
                Argument.againstLive: Self.booleanProperty("Compare with the app as installed now. Mutually exclusive with against_snapshot_id."),
                Argument.udid: Self.stringProperty("With against_live, the simulator to compare with. Defaults to the snapshot's own."),
                Argument.limit: .object([
                    "type": "integer",
                    "minimum": .int(1),
                    "description": .string("Most file changes to list, in path order. Defaults to \(Self.defaultDiffLimit). The summary counts all of them.")
                ])
            ], required: [Argument.snapshotId])
        case .restoreSnapshot:
            Self.schema([
                Argument.snapshotId: Self.snapshotIdProperty,
                Argument.udid: Self.stringProperty("Simulator to restore onto; the same app must be installed there. Defaults to the snapshot's own."),
                Argument.acceptWarnings: Self.booleanProperty(
                    "Restore even though the snapshot was taken from another app or OS version. Defaults to false, which returns the warnings and writes nothing."
                )
            ], required: [Argument.snapshotId])
        case .deleteSnapshot:
            Self.schema([Argument.snapshotId: Self.snapshotIdProperty], required: [Argument.snapshotId])
        }
    }

    // swiftlint:enable line_length

    var annotations: Tool.Annotations {
        switch self {
        case .listDevices:
            Self.readOnly("List Simulators")
        case .listApps:
            Self.readOnly("List Apps on a Simulator")
        case .findApp:
            Self.readOnly("Find an App")
        case .getAppContainers:
            Self.readOnly("Get App Container Paths")
        case .listAppGroups:
            Self.readOnly("List App Groups")
        case .listRecentApps:
            Self.readOnly("List Recent Apps")
        case .listCleanupCandidates:
            Self.readOnly("List Cleanup Candidates")
        case .readUserDefaults:
            Self.readOnly("Read UserDefaults")
        case .shutdownAllSimulators:
            Tool.Annotations(title: "Shut Down All Simulators", readOnlyHint: false, destructiveHint: false,
                             idempotentHint: true, openWorldHint: false)
        case .eraseDevice:
            Tool.Annotations(title: "Erase Simulator", readOnlyHint: false, destructiveHint: true,
                             idempotentHint: true, openWorldHint: false)
        case .eraseAllSimulators:
            Tool.Annotations(title: "Erase All Simulators", readOnlyHint: false, destructiveHint: true,
                             idempotentHint: true, openWorldHint: false)
        case .deleteCleanupCandidate:
            Tool.Annotations(title: "Delete Cleanup Candidate", readOnlyHint: false, destructiveHint: true,
                             idempotentHint: false, openWorldHint: false)
        case .listSnapshots:
            Self.readOnly("List Snapshots")
        case .captureSnapshot:
            Tool.Annotations(title: "Capture Snapshot", readOnlyHint: false, destructiveHint: false,
                             idempotentHint: false, openWorldHint: false)
        case .diffSnapshot:
            Self.readOnly("Diff Snapshot")
        case .restoreSnapshot:
            Tool.Annotations(title: "Restore Snapshot", readOnlyHint: false, destructiveHint: true,
                             idempotentHint: false, openWorldHint: false)
        case .deleteSnapshot:
            Tool.Annotations(title: "Delete Snapshot", readOnlyHint: false, destructiveHint: true,
                             idempotentHint: false, openWorldHint: false)
        }
    }

    static func readOnly(_ title: String) -> Tool.Annotations {
        Tool.Annotations(title: title, readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
    }

    static let udidProperty = stringProperty("Simulator UDID, as returned by list_devices.")
    static let bundleIdProperty = stringProperty("App bundle identifier, e.g. com.example.app.")
    static let snapshotIdProperty = stringProperty("A snapshot id, as returned by capture_snapshot or list_snapshots.")

    static func booleanProperty(_ description: String) -> Value {
        .object(["type": "boolean", "description": .string(description)])
    }

    static func stringProperty(_ description: String, choices: [String]? = nil) -> Value {
        var property: [String: Value] = ["type": "string", "description": .string(description)]
        if let choices {
            property["enum"] = .array(choices.map { .string($0) })
        }
        return .object(property)
    }

    static func schema(_ properties: [String: Value] = [:], required: [String] = []) -> Value {
        .object([
            "type": "object",
            "properties": .object(properties),
            "required": .array(required.map { .string($0) }),
            "additionalProperties": false
        ])
    }
}
