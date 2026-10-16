import Foundation

public enum SimulatorCleanupReason: String, CaseIterable, Sendable, Hashable {
    case missingRuntime
    case missingDeviceType
    case unavailable
    case orphanedDirectory
    case missingDevicePlist
    case unreadableDeviceMetadata

    public var title: String {
        switch self {
        case .missingRuntime:
            "Missing Runtime"
        case .missingDeviceType:
            "Missing Device Type"
        case .unavailable:
            "Unavailable"
        case .orphanedDirectory:
            "Orphaned Directory"
        case .missingDevicePlist:
            "Missing Metadata"
        case .unreadableDeviceMetadata:
            "Unreadable Metadata"
        }
    }

    public var priority: Int {
        switch self {
        case .missingRuntime:
            6
        case .missingDeviceType:
            5
        case .unavailable:
            4
        case .orphanedDirectory:
            3
        case .missingDevicePlist:
            2
        case .unreadableDeviceMetadata:
            1
        }
    }
}

public enum SimulatorCleanupDeletionMethod: Sendable, Hashable {
    case simctlDelete(String)
    case trashDirectory(URL)
}

public struct SimulatorCleanupCandidate: Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let udid: String?
    public let simulatorPlatform: SimulatorPlatform?
    public let osVersion: String?
    public let lastBootedAt: Date?
    public let diskUsageBytes: Int64?
    public let reasons: [SimulatorCleanupReason]
    public let detailMessage: String?
    public let deletionMethod: SimulatorCleanupDeletionMethod

    public init(
        id: String,
        name: String,
        udid: String?,
        simulatorPlatform: SimulatorPlatform?,
        osVersion: String?,
        lastBootedAt: Date?,
        diskUsageBytes: Int64?,
        reasons: [SimulatorCleanupReason],
        detailMessage: String?,
        deletionMethod: SimulatorCleanupDeletionMethod
    ) {
        self.id = id
        self.name = name
        self.udid = udid
        self.simulatorPlatform = simulatorPlatform
        self.osVersion = osVersion
        self.lastBootedAt = lastBootedAt
        self.diskUsageBytes = diskUsageBytes
        self.reasons = Array(Set(reasons)).sorted { lhs, rhs in
            lhs.priority > rhs.priority
        }
        self.detailMessage = detailMessage
        self.deletionMethod = deletionMethod
    }

    public var reasonSummary: String {
        reasons.map(\.title).joined(separator: ", ")
    }

    public var formattedPlatform: String? {
        guard let simulatorPlatform else {
            return nil
        }

        switch simulatorPlatform {
        case .iPhone:
            return "iPhone"
        case .iPad:
            return "iPad"
        case .watch:
            return "Apple Watch"
        case .appleTV:
            return "Apple TV"
        case .visionPro:
            return "Apple Vision Pro"
        case .iPodTouch:
            return "iPod touch"
        }
    }

    public var formattedDiskUsage: String? {
        guard let diskUsageBytes else {
            return nil
        }

        return ByteCountFormatter.string(fromByteCount: diskUsageBytes, countStyle: .file)
    }

    public var versionGroupTitle: String {
        osVersion ?? "Unknown OS"
    }

    public var versionSortComponents: [Int] {
        guard let osVersion else {
            return []
        }

        return osVersion
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
    }

    public func updatingDiskUsageBytes(_ diskUsageBytes: Int64?) -> SimulatorCleanupCandidate {
        SimulatorCleanupCandidate(
            id: id,
            name: name,
            udid: udid,
            simulatorPlatform: simulatorPlatform,
            osVersion: osVersion,
            lastBootedAt: lastBootedAt,
            diskUsageBytes: diskUsageBytes,
            reasons: reasons,
            detailMessage: detailMessage,
            deletionMethod: deletionMethod
        )
    }
}
