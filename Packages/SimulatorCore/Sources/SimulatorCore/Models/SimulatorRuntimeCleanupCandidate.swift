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
        sizeBytes.map(Self.formattedBytes)
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
        candidates.totalSizeBytes
    }
}

/// Numeric version ordering. `26.10` has to sort after `26.9`, which a string compare gets wrong.
public enum SimulatorRuntimeVersion {
    public static func components(of version: String) -> [Int] {
        version.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    }

    /// `true` when `lhs` is a strictly lower version than `rhs`; missing components count as zero.
    public static func isLower(_ lhs: String, than rhs: String) -> Bool {
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

/// An Apple build number such as `23E254a`: major digits, a letter, minor digits, and an optional
/// trailing letter for a patched re-release.
///
/// A plain numeric or string compare gets beta builds wrong. A beta carries a long minor number
/// (`23A5330a`) while the release it precedes carries a short one (`23A344`), so the beta compares
/// as "newer" than the release. Builds of those two shapes are therefore not ordered against each
/// other here at all.
struct SimulatorRuntimeBuild: Equatable {
    /// Minor numbers of this many digits or more are what Apple's pre-release builds use.
    private static let preReleaseMinorDigits = 4

    let major: Int
    let letter: Character
    let minor: Int
    let suffix: Character?
    private let minorDigitCount: Int

    init?(_ build: String) {
        let scalars = Array(build)
        var index = 0

        func digits() -> String {
            var result = ""
            while index < scalars.count, scalars[index].isASCII, scalars[index].isNumber {
                result.append(scalars[index])
                index += 1
            }
            return result
        }

        let majorDigits = digits()
        guard index < scalars.count, scalars[index].isLetter, scalars[index].isASCII else {
            return nil
        }

        let letter = scalars[index]
        index += 1
        let minorDigits = digits()

        guard let major = Int(majorDigits), let minor = Int(minorDigits) else {
            return nil
        }

        var suffix: Character?
        if index < scalars.count {
            guard scalars[index].isLetter, scalars[index].isASCII, index == scalars.count - 1 else {
                return nil
            }

            suffix = scalars[index]
        }

        self.major = major
        self.letter = letter
        self.minor = minor
        self.suffix = suffix
        self.minorDigitCount = minorDigits.count
    }

    private var looksPreRelease: Bool {
        minorDigitCount >= Self.preReleaseMinorDigits
    }

    /// `true` only when both builds are comparable and `self` is the later one.
    func isNewer(than other: SimulatorRuntimeBuild?) -> Bool {
        guard let other, looksPreRelease == other.looksPreRelease else {
            return false
        }

        if major != other.major {
            return major > other.major
        }

        if letter != other.letter {
            return letter > other.letter
        }

        if minor != other.minor {
            return minor > other.minor
        }

        // `23E254a` is a re-release of `23E254`.
        return (suffix.map { String($0) } ?? "") > (other.suffix.map { String($0) } ?? "")
    }
}

extension Sequence<SimulatorRuntimeCleanupCandidate> {
    /// The size the candidates would free; those whose size is unknown count as zero.
    public var totalSizeBytes: Int64 {
        compactMap(\.sizeBytes).reduce(0, +)
    }
}

extension SimulatorRuntimeCleanupCandidate {
    public static func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
