import Foundation

enum SimulatorCleanupReason: String, CaseIterable, Sendable, Hashable {
    case missingRuntime
    case missingDeviceType
    case unavailable
    case orphanedDirectory
    case missingDevicePlist
    case unreadableDeviceMetadata

    var title: String {
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

    var priority: Int {
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

enum SimulatorCleanupDeletionMethod: Sendable, Hashable {
    case simctlDelete(String)
    case trashDirectory(URL)
}

struct SimulatorCleanupCandidate: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let udid: String?
    let simulatorPlatform: SimulatorPlatform?
    let osVersion: String?
    let lastBootedAt: Date?
    let diskUsageBytes: Int64?
    let reasons: [SimulatorCleanupReason]
    let detailMessage: String?
    let deletionMethod: SimulatorCleanupDeletionMethod

    init(
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

    var reasonSummary: String {
        reasons.map(\.title).joined(separator: ", ")
    }

    var formattedPlatform: String? {
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

    var formattedDiskUsage: String? {
        guard let diskUsageBytes else {
            return nil
        }

        return ByteCountFormatter.string(fromByteCount: diskUsageBytes, countStyle: .file)
    }

    func updatingDiskUsageBytes(_ diskUsageBytes: Int64?) -> SimulatorCleanupCandidate {
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
