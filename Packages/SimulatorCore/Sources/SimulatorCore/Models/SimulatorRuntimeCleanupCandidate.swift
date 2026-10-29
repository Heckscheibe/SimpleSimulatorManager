import Foundation

/// Why a simulator runtime disk image is offered for removal. Each case mirrors a filter of
/// `xcrun simctl runtime delete`, so the app never flags an image `simctl` itself would keep.
public enum SimulatorRuntimeCleanupReason: String, CaseIterable, Sendable, Hashable {
    case unusable
    case superseded
    case unused

    public var title: String {
        switch self {
        case .unusable:
            "Unusable"
        case .superseded:
            "Superseded"
        case .unused:
            "Unused"
        }
    }

    public var priority: Int {
        switch self {
        case .unusable:
            3
        case .superseded:
            2
        case .unused:
            1
        }
    }
}

public struct SimulatorRuntimeCleanupCandidate: Identifiable, Sendable, Hashable {
    public let id: String
    /// The disk image's identifier, which is what `simctl runtime delete` takes.
    public let imageIdentifier: String
    public let runtimeIdentifier: String
    public let platformName: String
    public let version: String
    public let build: String
    public let sizeBytes: Int64?
    public let lastUsedAt: Date?
    public let reasons: [SimulatorRuntimeCleanupReason]
    /// Simulators that would lose their runtime, because no other usable image provides it.
    public let affectedSimulatorCount: Int
    /// How many of those are running now; `simctl` shuts them down before removing the image.
    public let bootedSimulatorCount: Int
    public let detailMessage: String?

    public init(
        imageIdentifier: String,
        runtimeIdentifier: String,
        platformName: String,
        version: String,
        build: String,
        sizeBytes: Int64?,
        lastUsedAt: Date?,
        reasons: [SimulatorRuntimeCleanupReason],
        affectedSimulatorCount: Int,
        bootedSimulatorCount: Int,
        detailMessage: String?
    ) {
        self.id = "runtime-\(imageIdentifier)"
        self.imageIdentifier = imageIdentifier
        self.runtimeIdentifier = runtimeIdentifier
        self.platformName = platformName
        self.version = version
        self.build = build
        self.sizeBytes = sizeBytes
        self.lastUsedAt = lastUsedAt
        self.reasons = Array(Set(reasons)).sorted { $0.priority > $1.priority }
        self.affectedSimulatorCount = affectedSimulatorCount
        self.bootedSimulatorCount = bootedSimulatorCount
        self.detailMessage = detailMessage
    }

    public var name: String {
        "\(platformName) \(version) (\(build))"
    }

    public var reasonSummary: String {
        reasons.map(\.title).joined(separator: ", ")
    }

    public var formattedSize: String? {
        sizeBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
    }

    /// Groups the runtime list by platform, so iOS and watchOS images are not mixed in one bucket.
    public var versionGroupTitle: String {
        platformName
    }

    public var versionSortComponents: [Int] {
        SimulatorRuntimeVersion.components(of: version)
    }
}

public struct SimulatorRuntimeCleanupScan: Sendable, Equatable {
    public let candidates: [SimulatorRuntimeCleanupCandidate]
    /// Runtime images `simctl` reported, whether or not they qualified.
    public let checkedRuntimeCount: Int

    public init(candidates: [SimulatorRuntimeCleanupCandidate], checkedRuntimeCount: Int) {
        self.candidates = candidates
        self.checkedRuntimeCount = checkedRuntimeCount
    }

    public var totalReclaimableBytes: Int64 {
        candidates.compactMap(\.sizeBytes).reduce(0, +)
    }
}

/// Numeric version ordering. `26.10` has to sort after `26.9`, which a string compare gets wrong.
enum SimulatorRuntimeVersion {
    static func components(of version: String) -> [Int] {
        version.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    }

    /// `true` when `lhs` is a strictly lower version than `rhs`; missing components count as zero.
    static func isLower(_ lhs: String, than rhs: String) -> Bool {
        let left = components(of: lhs)
        let right = components(of: rhs)

        for index in 0 ..< max(left.count, right.count) {
            let leftValue = index < left.count ? left[index] : 0
            let rightValue = index < right.count ? right[index] : 0

            if leftValue != rightValue {
                return leftValue < rightValue
            }
        }

        return false
    }
}
