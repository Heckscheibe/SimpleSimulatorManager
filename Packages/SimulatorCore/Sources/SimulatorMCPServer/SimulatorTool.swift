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

    public var flag: String? {
        switch self {
        case .alwaysAvailable:
            nil
        case .userDefaults:
            ServerOptions.allowUserDefaultsFlag
        case .destructive:
            ServerOptions.allowDestructiveFlag
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

    enum Argument {
        static let platform = "platform"
        static let state = "state"
        static let udid = "udid"
        static let bundleId = "bundle_id"
        static let appGroupId = "app_group_id"
        static let domain = "domain"
        static let limit = "limit"
        static let id = "id"
    }

    public var gate: ToolGate {
        switch self {
        case .listDevices, .listApps, .findApp, .getAppContainers, .listAppGroups, .listRecentApps,
             .listCleanupCandidates, .shutdownAllSimulators:
            .alwaysAvailable
        case .readUserDefaults:
            .userDefaults
        case .eraseDevice, .eraseAllSimulators, .deleteCleanupCandidate:
            .destructive
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
        }
    }

    // swiftlint:enable line_length

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
        }
    }

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
        }
    }

    static func readOnly(_ title: String) -> Tool.Annotations {
        Tool.Annotations(title: title, readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
    }

    static let udidProperty = stringProperty("Simulator UDID, as returned by list_devices.")
    static let bundleIdProperty = stringProperty("App bundle identifier, e.g. com.example.app.")

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
