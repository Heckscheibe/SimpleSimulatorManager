//
//  ToolRegistry.swift
//  SimulatorMCPServer
//

import Foundation
import MCP
import os
import SimulatorCore

/// The tools a server instance offers, and how each call is validated and answered.
///
/// A gated tool whose flag was not passed is left out of the listing; calling it anyway is an
/// `isError` result naming that flag, so an agent can tell the user what to change.
public struct ToolRegistry: Sendable {
    public let options: ServerOptions
    private let service: any SimulatorQuerying

    public init(options: ServerOptions, service: any SimulatorQuerying = SimulatorQueryService()) {
        self.options = options
        self.service = service
    }

    public var enabledTools: [SimulatorTool] {
        SimulatorTool.allCases.filter { $0.gate.isOpen(for: options) }
    }

    public var tools: [Tool] {
        enabledTools.map(\.definition)
    }

    public func call(_ name: String, arguments: [String: Value]?) async -> CallTool.Result {
        guard let tool = SimulatorTool(rawValue: name) else {
            return JSONOutput.error("Unknown tool \(name).")
        }
        guard tool.gate.isOpen(for: options) else {
            let flag = tool.gate.flag ?? ""
            return JSONOutput.error("Tool \(name) is disabled. Start the server with \(flag) to enable it.")
        }

        do {
            let arguments = try ToolArguments(arguments, allowedNames: tool.argumentNames)
            return try await call(tool, with: arguments)
        } catch {
            os_log("MCP tool %{public}@ failed: %{public}@", name, error.localizedDescription)
            return JSONOutput.error(error.localizedDescription)
        }
    }
}

// MARK: - Dispatch

private extension ToolRegistry {
    typealias Argument = SimulatorTool.Argument

    func call(_ tool: SimulatorTool, with arguments: ToolArguments) async throws -> CallTool.Result {
        switch tool {
        case .listDevices:
            let platform = try arguments.optionalChoice(Argument.platform, from: SimulatorPlatform.allIdentifiers)
            let state = try arguments.optionalChoice(Argument.state, from: DeviceState.allIdentifiers)
            let devices = try await service.devices().filter { device in
                (platform == nil || device.platform == platform) && (state == nil || device.state == state)
            }
            return try JSONOutput.result(DeviceList(devices: devices))

        case .listApps:
            let udid = try arguments.requiredString(Argument.udid)
            return try JSONOutput.result(AppList(udid: udid, apps: await service.apps(onDeviceWithUdid: udid)))

        case .findApp:
            let bundleIdentifier = try arguments.requiredString(Argument.bundleId)
            let installations = try await service.installations(ofBundleIdentifier: bundleIdentifier)
            return try JSONOutput.result(AppInstallationList(bundleIdentifier: bundleIdentifier, installations: installations))

        case .getAppContainers:
            let udid = try arguments.requiredString(Argument.udid)
            let bundleIdentifier = try arguments.requiredString(Argument.bundleId)
            return try JSONOutput.result(await service.containers(ofBundleIdentifier: bundleIdentifier, onDeviceWithUdid: udid))

        case .listAppGroups:
            let udid = try arguments.requiredString(Argument.udid)
            return try JSONOutput.result(AppGroupList(udid: udid, appGroups: await service.appGroups(onDeviceWithUdid: udid)))

        case .listRecentApps:
            let limit = try min(max(arguments.optionalInteger(Argument.limit) ?? RecentApps.maxCount, 1), RecentApps.maxCount)
            return try JSONOutput.result(RecentAppList(recentApps: await service.recentApps(limit: limit)))

        case .listCleanupCandidates:
            return try JSONOutput.result(CleanupCandidateList(candidates: await service.cleanupCandidates()))

        case .shutdownAllSimulators:
            try await service.shutDownAllSimulators()
            return try JSONOutput.result(Status(status: "All running simulators were shut down."))

        case .readUserDefaults:
            return try await readUserDefaults(with: arguments)

        case .eraseDevice:
            let udid = try arguments.requiredString(Argument.udid)
            try await service.eraseDevice(withUdid: udid)
            return try JSONOutput.result(Status(status: "Simulator \(udid) was shut down and erased."))

        case .eraseAllSimulators:
            try await service.eraseAllSimulators()
            return try JSONOutput.result(Status(status: "All simulators were shut down and erased."))

        case .deleteCleanupCandidate:
            let id = try arguments.requiredString(Argument.id)
            return try JSONOutput.result(DeletedCandidate(deleted: await service.deleteCleanupCandidate(withId: id)))
        }
    }

    /// The text content is the export verbatim, so it is byte-for-byte what the menu copies.
    func readUserDefaults(with arguments: ToolArguments) async throws -> CallTool.Result {
        let udid = try arguments.requiredString(Argument.udid)
        let bundleIdentifier = try arguments.optionalString(Argument.bundleId)
        let appGroupIdentifier = try arguments.optionalString(Argument.appGroupId)
        let domain = try arguments.optionalString(Argument.domain)

        let subject: UserDefaultsSubject
        switch (bundleIdentifier, appGroupIdentifier) {
        case let (bundleIdentifier?, nil):
            subject = .app(bundleIdentifier: bundleIdentifier)
        case let (nil, appGroupIdentifier?):
            subject = .appGroup(identifier: appGroupIdentifier)
        default:
            throw ToolArgumentError(message: "Pass exactly one of \(Argument.bundleId) or \(Argument.appGroupId).")
        }

        let json = try await service.userDefaultsJSON(of: subject, onDeviceWithUdid: udid, domain: domain)

        return try JSONOutput.result(json: Data(json.utf8))
    }
}

// MARK: - Result envelopes

// Structured content has to be a JSON object, so lists are wrapped and keep their context.

private struct DeviceList: Encodable {
    let devices: [DeviceDTO]
}

private struct AppList: Encodable {
    let udid: String
    let apps: [AppDTO]
}

private struct AppInstallationList: Encodable {
    let bundleIdentifier: String
    let installations: [AppInstallationDTO]
}

private struct AppGroupList: Encodable {
    let udid: String
    let appGroups: [AppGroupDTO]
}

private struct RecentAppList: Encodable {
    let recentApps: [RecentAppDTO]
}

private struct CleanupCandidateList: Encodable {
    let candidates: [CleanupCandidateDTO]
}

private struct DeletedCandidate: Encodable {
    let deleted: CleanupCandidateDTO
}

private struct Status: Encodable {
    let status: String
}
