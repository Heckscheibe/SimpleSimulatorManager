import Foundation
import os

protocol SimulatorCleanupServing: AnyObject, Sendable {
    func loadCleanupCandidates() async throws -> [SimulatorCleanupCandidate]
    func deleteCleanupCandidate(_ candidate: SimulatorCleanupCandidate) async throws
}

struct SimctlDeviceRecord: Sendable, Equatable {
    let udid: String
    let name: String
    let state: String
    let runtimeIdentifier: String
    let deviceTypeIdentifier: String
    let dataPath: String?
    let dataPathSize: Int64?
    let isAvailable: Bool
    let availabilityError: String?
}

struct SimctlRuntimeRecord: Decodable, Sendable, Equatable {
    let identifier: String
    let isAvailable: Bool
}

struct SimulatorDirectoryMetadata: Sendable, Equatable {
    let udid: String
    let name: String
    let runtimeIdentifier: String
    let deviceTypeIdentifier: String
    let lastBootedAt: Date?

    var simulatorPlatform: SimulatorPlatform {
        SimulatorPlatform(from: deviceTypeIdentifier)
    }

    var osVersion: String {
        SimulatorPaths.formattedOSVersion(from: runtimeIdentifier)
    }
}

struct SimulatorDirectoryRecord: Sendable, Equatable {
    enum MetadataStatus: Sendable, Equatable {
        case decoded(SimulatorDirectoryMetadata)
        case missingDevicePlist
        case unreadableDevicePlist
    }

    let udid: String
    let directoryURL: URL
    let metadataStatus: MetadataStatus
    let diskUsageBytes: Int64?

    var metadata: SimulatorDirectoryMetadata? {
        guard case let .decoded(metadata) = metadataStatus else {
            return nil
        }

        return metadata
    }
}

final class SimulatorCleanupService: SimulatorCleanupServing {
    func loadCleanupCandidates() async throws -> [SimulatorCleanupCandidate] {
        os_log("Cleanup service started loading candidates")
        async let simctlDevices = loadSimctlDevices()
        async let availableRuntimeIdentifiers = loadAvailableRuntimeIdentifiers()
        async let directoryRecords = loadDirectoryRecords()

        let loadedSimctlDevices = try await simctlDevices
        let loadedRuntimeIdentifiers = try await availableRuntimeIdentifiers
        let loadedDirectoryRecords = try await directoryRecords

        os_log(
            "Cleanup service inputs loaded. devices=%{public}ld runtimes=%{public}ld directories=%{public}ld",
            loadedSimctlDevices.count,
            loadedRuntimeIdentifiers.count,
            loadedDirectoryRecords.count
        )

        let candidates = Self.buildCleanupCandidates(
            simctlDevices: loadedSimctlDevices,
            availableRuntimeIdentifiers: loadedRuntimeIdentifiers,
            directoryRecords: loadedDirectoryRecords
        )

        os_log("Cleanup service built %{public}ld candidates", candidates.count)
        return candidates
    }

    func deleteCleanupCandidate(_ candidate: SimulatorCleanupCandidate) async throws {
        os_log("Cleanup service deleting candidate %{public}@ using %{public}@", candidate.id, String(describing: candidate.deletionMethod))
        switch candidate.deletionMethod {
        case let .simctlDelete(udid):
            _ = try await runSimctlCommand(arguments: ["delete", udid])
            os_log("Cleanup service deleted simulator %{public}@ via simctl", udid)
        case let .trashDirectory(directoryURL):
            try await Task.detached(priority: .userInitiated) {
                var resultingItemURL: NSURL?
                try FileManager.default.trashItem(at: directoryURL, resultingItemURL: &resultingItemURL)
            }.value
            os_log("Cleanup service moved directory to trash: %{public}@", directoryURL.path)
        }
    }

    static func buildCleanupCandidates(
        simctlDevices: [SimctlDeviceRecord],
        availableRuntimeIdentifiers: Set<String>,
        directoryRecords: [SimulatorDirectoryRecord]
    ) -> [SimulatorCleanupCandidate] {
        let directoryRecordsByUDID = Dictionary(uniqueKeysWithValues: directoryRecords.map { ($0.udid, $0) })
        let simctlUDIDs = Set(simctlDevices.map(\.udid))

        var candidates = simctlDevices.compactMap { device in
            makeUnavailableDeviceCandidate(
                from: device,
                availableRuntimeIdentifiers: availableRuntimeIdentifiers,
                directoryRecord: directoryRecordsByUDID[device.udid]
            )
        }

        candidates.append(contentsOf: directoryRecords.compactMap { directoryRecord in
            guard !simctlUDIDs.contains(directoryRecord.udid) else {
                return nil
            }

            return makeOrphanedDirectoryCandidate(
                from: directoryRecord,
                availableRuntimeIdentifiers: availableRuntimeIdentifiers
            )
        })

        return candidates.sorted(by: sortCandidates)
    }

    private func loadSimctlDevices() async throws -> [SimctlDeviceRecord] {
        os_log("Cleanup service loading simctl devices")
        let output = try await runSimctlCommand(arguments: ["list", "devices", "--json"])
        let data = Data(output.utf8)
        let response = try JSONDecoder().decode(SimctlDevicesResponse.self, from: data)

        let devices = response.devices.flatMap { runtimeIdentifier, devices in
            devices.map { device in
                SimctlDeviceRecord(
                    udid: device.udid,
                    name: device.name,
                    state: device.state,
                    runtimeIdentifier: runtimeIdentifier,
                    deviceTypeIdentifier: device.deviceTypeIdentifier,
                    dataPath: device.dataPath,
                    dataPathSize: device.dataPathSize,
                    isAvailable: device.isAvailable,
                    availabilityError: device.availabilityError
                )
            }
        }

        os_log("Cleanup service loaded %{public}ld simctl devices", devices.count)
        return devices
    }

    private func loadAvailableRuntimeIdentifiers() async throws -> Set<String> {
        os_log("Cleanup service loading available runtimes")
        let output = try await runSimctlCommand(arguments: ["list", "runtimes", "--json"])
        let data = Data(output.utf8)
        let response = try JSONDecoder().decode(SimctlRuntimesResponse.self, from: data)

        let availableRuntimeIdentifiers = Set(response.runtimes.filter(\.isAvailable).map(\.identifier))
        os_log("Cleanup service loaded %{public}ld available runtimes", availableRuntimeIdentifiers.count)
        return availableRuntimeIdentifiers
    }

    private func loadDirectoryRecords() async throws -> [SimulatorDirectoryRecord] {
        os_log("Cleanup service loading simulator directories")
        return try await Task.detached(priority: .userInitiated) {
            guard let devicesDirectoryURL = SimulatorPaths.coreSimulatorDevicesDirectoryURL() else {
                os_log("Cleanup service could not determine CoreSimulator devices directory URL")
                return [SimulatorDirectoryRecord]()
            }
            guard FileManager.default.fileExists(atPath: devicesDirectoryURL.path) else {
                os_log("Cleanup service found no CoreSimulator devices directory at %{public}@", devicesDirectoryURL.path)
                return [SimulatorDirectoryRecord]()
            }

            let directoryURLs = try FileManager.default.contentsOfDirectory(
                at: devicesDirectoryURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            let directoryRecords = directoryURLs.compactMap(Self.makeDirectoryRecord(for:))
            os_log("Cleanup service loaded %{public}ld simulator directories", directoryRecords.count)
            return directoryRecords
        }.value
    }

    private func runSimctlCommand(arguments: [String]) async throws -> String {
        os_log("Cleanup service running simctl command: %{public}@", arguments.joined(separator: " "))

        let output = try await Task.detached(priority: .userInitiated) {
            try Process.execute(command: "/usr/bin/xcrun", arguments: ["simctl"] + arguments)
        }.value

        os_log(
            "Cleanup service completed simctl command: %{public}@ outputLength=%{public}ld",
            arguments.joined(separator: " "),
            output.count
        )

        return output
    }

    private static func makeUnavailableDeviceCandidate(
        from device: SimctlDeviceRecord,
        availableRuntimeIdentifiers: Set<String>,
        directoryRecord: SimulatorDirectoryRecord?
    ) -> SimulatorCleanupCandidate? {
        guard !device.isAvailable else {
            return nil
        }

        let availabilityError = device.availabilityError?.lowercased()
        var reasons: [SimulatorCleanupReason] = [.unavailable]

        if !availableRuntimeIdentifiers.contains(device.runtimeIdentifier) || availabilityError?.contains("runtime profile not found") == true {
            reasons.append(.missingRuntime)
        }

        if availabilityError?.contains("device type profile not found") == true {
            reasons.append(.missingDeviceType)
        }

        switch directoryRecord?.metadataStatus {
        case .missingDevicePlist?:
            reasons.append(.missingDevicePlist)
        case .unreadableDevicePlist?:
            reasons.append(.unreadableDeviceMetadata)
        case .decoded, nil:
            break
        }

        let metadata = directoryRecord?.metadata

        return SimulatorCleanupCandidate(
            id: "simctl-\(device.udid)",
            name: device.name,
            udid: device.udid,
            simulatorPlatform: metadata?.simulatorPlatform ?? SimulatorPlatform(from: device.deviceTypeIdentifier),
            osVersion: metadata?.osVersion ?? SimulatorPaths.formattedOSVersion(from: device.runtimeIdentifier),
            lastBootedAt: metadata?.lastBootedAt,
            diskUsageBytes: device.dataPathSize ?? directoryRecord?.diskUsageBytes,
            reasons: reasons,
            detailMessage: device.availabilityError,
            deletionMethod: .simctlDelete(device.udid)
        )
    }

    private static func makeOrphanedDirectoryCandidate(
        from directoryRecord: SimulatorDirectoryRecord,
        availableRuntimeIdentifiers: Set<String>
    ) -> SimulatorCleanupCandidate {
        var reasons: [SimulatorCleanupReason] = [.orphanedDirectory]
        var name = directoryRecord.directoryURL.lastPathComponent
        var simulatorPlatform: SimulatorPlatform?
        var osVersion: String?
        var lastBootedAt: Date?
        var detailMessage = "Simulator directory exists on disk but is not registered with CoreSimulator."

        switch directoryRecord.metadataStatus {
        case let .decoded(metadata):
            name = metadata.name
            simulatorPlatform = metadata.simulatorPlatform
            osVersion = metadata.osVersion
            lastBootedAt = metadata.lastBootedAt

            if !availableRuntimeIdentifiers.contains(metadata.runtimeIdentifier) {
                reasons.append(.missingRuntime)
                detailMessage = "Simulator runtime \(metadata.runtimeIdentifier) is no longer installed"
                    + " and the directory is not registered with CoreSimulator."
            }
        case .missingDevicePlist:
            reasons.append(.missingDevicePlist)
            detailMessage = "Simulator directory is missing device.plist metadata."
        case .unreadableDevicePlist:
            reasons.append(.unreadableDeviceMetadata)
            detailMessage = "Simulator directory contains unreadable device metadata."
        }

        return SimulatorCleanupCandidate(
            id: "orphan-\(directoryRecord.udid)",
            name: name,
            udid: directoryRecord.udid,
            simulatorPlatform: simulatorPlatform,
            osVersion: osVersion,
            lastBootedAt: lastBootedAt,
            diskUsageBytes: directoryRecord.diskUsageBytes,
            reasons: reasons,
            detailMessage: detailMessage,
            deletionMethod: .trashDirectory(directoryRecord.directoryURL)
        )
    }

    private static func makeDirectoryRecord(for directoryURL: URL) -> SimulatorDirectoryRecord? {
        guard UUID(uuidString: directoryURL.lastPathComponent) != nil else {
            return nil
        }

        let udid = directoryURL.lastPathComponent
        let metadataURL = directoryURL.appendingPathComponent(SimulatorPaths.devicePlistName)
        let diskUsageBytes = calculateDirectorySize(at: directoryURL)

        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            return SimulatorDirectoryRecord(
                udid: udid,
                directoryURL: directoryURL,
                metadataStatus: .missingDevicePlist,
                diskUsageBytes: diskUsageBytes
            )
        }

        do {
            let devicePlist = try CustomPropertyListDecoder().decode(CleanupDevicePlist.self, at: metadataURL)
            let metadata = SimulatorDirectoryMetadata(
                udid: devicePlist.udid ?? udid,
                name: devicePlist.name,
                runtimeIdentifier: devicePlist.runtime,
                deviceTypeIdentifier: devicePlist.deviceType,
                lastBootedAt: devicePlist.lastBootedAt
            )

            return SimulatorDirectoryRecord(
                udid: metadata.udid,
                directoryURL: directoryURL,
                metadataStatus: .decoded(metadata),
                diskUsageBytes: diskUsageBytes
            )
        } catch {
            return SimulatorDirectoryRecord(
                udid: udid,
                directoryURL: directoryURL,
                metadataStatus: .unreadableDevicePlist,
                diskUsageBytes: diskUsageBytes
            )
        }
    }

    private static func calculateDirectorySize(at directoryURL: URL) -> Int64? {
        let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        )

        var totalSize: Int64 = 0

        while let fileURL = enumerator?.nextObject() as? URL {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]),
                  resourceValues.isRegularFile == true else {
                continue
            }

            if let totalFileAllocatedSize = resourceValues.totalFileAllocatedSize {
                totalSize += Int64(totalFileAllocatedSize)
            } else if let fileAllocatedSize = resourceValues.fileAllocatedSize {
                totalSize += Int64(fileAllocatedSize)
            }
        }

        return totalSize == 0 ? nil : totalSize
    }

    private static func sortCandidates(lhs: SimulatorCleanupCandidate, rhs: SimulatorCleanupCandidate) -> Bool {
        let leftPriority = lhs.reasons.map(\.priority).max() ?? 0
        let rightPriority = rhs.reasons.map(\.priority).max() ?? 0

        if leftPriority != rightPriority {
            return leftPriority > rightPriority
        }

        if lhs.diskUsageBytes != rhs.diskUsageBytes {
            return (lhs.diskUsageBytes ?? 0) > (rhs.diskUsageBytes ?? 0)
        }

        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}

private struct SimctlDevicesResponse: Decodable {
    let devices: [String: [RawSimctlDevice]]
}

private struct RawSimctlDevice: Decodable {
    let udid: String
    let name: String
    let state: String
    let deviceTypeIdentifier: String
    let dataPath: String?
    let dataPathSize: Int64?
    let isAvailable: Bool
    let availabilityError: String?
}

private struct SimctlRuntimesResponse: Decodable {
    let runtimes: [SimctlRuntimeRecord]
}

private struct CleanupDevicePlist: DecodableURLContainer {
    let udid: String?
    let name: String
    let runtime: String
    let deviceType: String
    let lastBootedAt: Date?
    var url: URL?
}
