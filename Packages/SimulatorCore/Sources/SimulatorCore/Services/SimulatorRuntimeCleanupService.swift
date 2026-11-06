import Foundation
import os

public protocol SimulatorRuntimeCleanupServing: AnyObject, Sendable {
    func loadRuntimeCleanupScan() async throws -> SimulatorRuntimeCleanupScan
    func deleteRuntimeCandidate(_ candidate: SimulatorRuntimeCleanupCandidate) async throws
}

struct SimctlRuntimeImageRecord: Sendable, Equatable {
    let identifier: String
    let runtimeIdentifier: String
    let platformName: String
    let version: String
    let build: String
    let state: String
    let isDeletable: Bool
    let sizeBytes: Int64?
    let lastUsedAt: Date?

    var isReady: Bool {
        state.caseInsensitiveCompare("Ready") == .orderedSame
    }

    var isUnusable: Bool {
        state.caseInsensitiveCompare("Unusable") == .orderedSame
    }
}

struct RuntimeSimulatorRecord: Sendable, Equatable {
    let runtimeIdentifier: String
    let isBooted: Bool
}

/// Finds simulator runtime disk images that can be removed, and removes them.
///
/// Lives apart from ``SimulatorCleanupService`` on purpose: that one decides which *simulators* are
/// broken from CoreSimulator metadata, this one decides which *runtimes* are stale from
/// `simctl runtime list`. They share nothing but the process helper, and a runtime deletion is far
/// larger and can only be undone by downloading the image again.
public final class SimulatorRuntimeCleanupService: SimulatorRuntimeCleanupServing {
    /// `simctl runtime delete --notUsedSinceDays` takes the same kind of threshold.
    public static let defaultUnusedThresholdDays = 90

    private let unusedThresholdDays: Int
    private let now: @Sendable () -> Date

    /// Blocking process launches stay off the cooperative pool, as in ``SimulatorCleanupService``.
    private static let workQueue = DispatchQueue(
        label: "SimulatorRuntimeCleanupService.workQueue",
        qos: .userInitiated,
        attributes: .concurrent
    )

    public init(
        unusedThresholdDays: Int = SimulatorRuntimeCleanupService.defaultUnusedThresholdDays,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.unusedThresholdDays = unusedThresholdDays
        self.now = now
    }

    public func loadRuntimeCleanupScan() async throws -> SimulatorRuntimeCleanupScan {
        os_log("Runtime cleanup started loading")
        async let imageOutput = runSimctl(["runtime", "list", "-j"])
        async let deviceOutput = runSimctl(["list", "devices", "--json"])

        let images = try Self.parseRuntimeImages(from: Data(await imageOutput.utf8))
        let simulators = try Self.parseSimulators(from: Data(await deviceOutput.utf8))

        try Task.checkCancellation()

        let candidates = Self.buildCandidates(
            images: images,
            simulators: simulators,
            now: now(),
            unusedThresholdDays: unusedThresholdDays
        )

        os_log("Runtime cleanup checked %{public}ld runtimes, %{public}ld candidates", images.count, candidates.count)
        return SimulatorRuntimeCleanupScan(candidates: candidates, checkedRuntimeCount: images.count)
    }

    public func deleteRuntimeCandidate(_ candidate: SimulatorRuntimeCleanupCandidate) async throws {
        // The identifier ends up as a `simctl` argument. Refuse anything that is not an image UUID
        // so a malformed value can never be read as an option such as `--all`.
        guard UUID(uuidString: candidate.imageIdentifier) != nil else {
            throw NSError(
                domain: "SimulatorRuntimeCleanup",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "\(candidate.name) has no valid runtime identifier."]
            )
        }

        os_log("Runtime cleanup deleting %{public}@", candidate.imageIdentifier)
        _ = try await runSimctl(["runtime", "delete", candidate.imageIdentifier])
        os_log("Runtime cleanup deleted %{public}@", candidate.imageIdentifier)
    }

    private func runSimctl(_ arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            Self.workQueue.async {
                continuation.resume(with: Result {
                    try Process.execute(command: "/usr/bin/xcrun", arguments: ["simctl"] + arguments)
                })
            }
        }
    }
}

// MARK: - Qualification

extension SimulatorRuntimeCleanupService {
    static func buildCandidates(
        images: [SimctlRuntimeImageRecord],
        simulators: [RuntimeSimulatorRecord],
        now: Date,
        unusedThresholdDays: Int
    ) -> [SimulatorRuntimeCleanupCandidate] {
        // Reasons first, for every image, because whether deleting one strands simulators depends
        // on whether the *other* images of that runtime survive.
        var reasonsByImage: [String: [SimulatorRuntimeCleanupReason]] = [:]
        var supersededBy: [String: SimctlRuntimeImageRecord] = [:]

        // An image still downloading, staging or verifying is not stale, whatever its version or
        // last-used date say; only settled images (Ready or Unusable) can qualify.
        for image in images where image.isDeletable && (image.isReady || image.isUnusable) {
            var reasons: [SimulatorRuntimeCleanupReason] = []

            if image.isUnusable {
                reasons.append(.unusable)
            }

            if let newer = newerReadyImage(than: image, in: images) {
                reasons.append(.superseded)
                supersededBy[image.identifier] = newer
            }

            if let lastUsedAt = image.lastUsedAt,
               now.timeIntervalSince(lastUsedAt) > TimeInterval(unusedThresholdDays) * 86400 {
                reasons.append(.unused)
            }

            if !reasons.isEmpty {
                reasonsByImage[image.identifier] = reasons
            }
        }

        let candidates = images.compactMap { image -> SimulatorRuntimeCleanupCandidate? in
            guard let reasons = reasonsByImage[image.identifier] else {
                return nil
            }

            // An image that nothing else replaces takes its simulators with it. A broken image
            // already left them unavailable, so removing it costs them nothing further.
            let hasSurvivor = images.contains { other in
                other.identifier != image.identifier
                    && other.runtimeIdentifier == image.runtimeIdentifier
                    && other.isReady
                    && reasonsByImage[other.identifier] == nil
            }
            let affected = image.isUnusable || hasSurvivor
                ? []
                : simulators.filter { $0.runtimeIdentifier == image.runtimeIdentifier }

            return SimulatorRuntimeCleanupCandidate(
                imageIdentifier: image.identifier,
                runtimeIdentifier: image.runtimeIdentifier,
                platformName: image.platformName,
                version: image.version,
                build: image.build,
                sizeBytes: image.sizeBytes,
                lastUsedAt: image.lastUsedAt,
                reasons: reasons,
                affectedSimulatorCount: affected.count,
                bootedSimulatorCount: affected.count(where: \.isBooted),
                detailMessage: detailMessage(
                    for: image,
                    reasons: reasons,
                    supersededBy: supersededBy[image.identifier],
                    replacementIsAlsoListed: supersededBy[image.identifier].map { reasonsByImage[$0.identifier] != nil } ?? false,
                    now: now
                )
            )
        }

        return candidates.sorted { lhs, rhs in
            let leftPriority = lhs.reasons.map(\.priority).max() ?? 0
            let rightPriority = rhs.reasons.map(\.priority).max() ?? 0

            if leftPriority != rightPriority {
                return leftPriority > rightPriority
            }

            if lhs.sizeBytes != rhs.sizeBytes {
                return (lhs.sizeBytes ?? 0) > (rhs.sizeBytes ?? 0)
            }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// The best image of the same runtime that replaces `image`, if any. Only a *ready* image can
    /// replace another: a newer but broken one would leave the user with nothing to run.
    private static func newerReadyImage(
        than image: SimctlRuntimeImageRecord,
        in images: [SimctlRuntimeImageRecord]
    ) -> SimctlRuntimeImageRecord? {
        images
            .filter { other in
                other.identifier != image.identifier
                    && other.runtimeIdentifier == image.runtimeIdentifier
                    && other.isReady
                    && isNewer(other, than: image)
            }
            .max { isNewer($1, than: $0) }
    }

    /// Higher version wins; for the same version the higher build does, when the two builds can be
    /// ordered at all (see ``SimulatorRuntimeBuild``). Two builds that cannot be ordered replace
    /// neither, which keeps both: deleting the wrong one is far worse than keeping an extra one.
    private static func isNewer(_ lhs: SimctlRuntimeImageRecord, than rhs: SimctlRuntimeImageRecord) -> Bool {
        if SimulatorRuntimeVersion.isLower(rhs.version, than: lhs.version) {
            return true
        }

        if SimulatorRuntimeVersion.isLower(lhs.version, than: rhs.version) {
            return false
        }

        return SimulatorRuntimeBuild(lhs.build)?.isNewer(than: SimulatorRuntimeBuild(rhs.build)) ?? false
    }

    private static func detailMessage(
        for image: SimctlRuntimeImageRecord,
        reasons: [SimulatorRuntimeCleanupReason],
        supersededBy newer: SimctlRuntimeImageRecord?,
        replacementIsAlsoListed: Bool,
        now: Date
    ) -> String {
        var sentences: [String] = []

        if reasons.contains(.unusable) {
            sentences.append("CoreSimulator marks this runtime image as unusable.")
        }

        if reasons.contains(.superseded), let newer {
            let newerName = "\(newer.platformName) \(newer.version) (\(newer.build))"
            sentences.append(replacementIsAlsoListed
                ? "\(newerName) of the same runtime is newer, but is listed for removal too."
                : "\(newerName) of the same runtime is installed.")
        }

        if reasons.contains(.unused), let lastUsedAt = image.lastUsedAt {
            let days = Int(now.timeIntervalSince(lastUsedAt) / 86400)
            sentences.append("Not used for \(days) days.")
        }

        return sentences.joined(separator: " ")
    }
}

// MARK: - Parsing

extension SimulatorRuntimeCleanupService {
    static func parseRuntimeImages(from data: Data) throws -> [SimctlRuntimeImageRecord] {
        let raw = try JSONDecoder().decode([String: RawRuntimeImage].self, from: data)
        let formatter = ISO8601DateFormatter()

        return raw.map { key, image in
            let runtimeIdentifier = image.runtimeIdentifier ?? ""

            return SimctlRuntimeImageRecord(
                identifier: image.identifier ?? key,
                runtimeIdentifier: runtimeIdentifier,
                platformName: platformName(runtimeIdentifier: runtimeIdentifier, platformIdentifier: image.platformIdentifier),
                version: image.version ?? "",
                build: image.build ?? "",
                state: image.state ?? "",
                isDeletable: image.deletable,
                sizeBytes: image.sizeBytes,
                lastUsedAt: image.lastUsedAt.flatMap { formatter.date(from: $0) }
            )
        }
        .sorted { $0.identifier < $1.identifier }
    }

    static func parseSimulators(from data: Data) throws -> [RuntimeSimulatorRecord] {
        let response = try JSONDecoder().decode(RawDevicesResponse.self, from: data)

        return response.devices.flatMap { runtimeIdentifier, devices in
            devices.map { RuntimeSimulatorRecord(runtimeIdentifier: runtimeIdentifier, isBooted: $0.state == "Booted") }
        }
    }

    private static func platformName(runtimeIdentifier: String, platformIdentifier: String?) -> String {
        if let component = runtimeIdentifier.split(separator: ".").last,
           let platform = component.split(separator: "-").first {
            // The runtime identifier still uses the codename for visionOS.
            return platform == "xrOS" ? "visionOS" : String(platform)
        }

        switch platformIdentifier {
        case "com.apple.platform.iphonesimulator": return "iOS"
        case "com.apple.platform.watchsimulator": return "watchOS"
        case "com.apple.platform.appletvsimulator": return "tvOS"
        case "com.apple.platform.xrsimulator": return "visionOS"
        default: return "Runtime"
        }
    }
}

private struct RawRuntimeImage: Decodable {
    let identifier: String?
    let runtimeIdentifier: String?
    let platformIdentifier: String?
    let version: String?
    let build: String?
    let state: String?
    let deletable: Bool
    let sizeBytes: Int64?
    let lastUsedAt: String?

    enum CodingKeys: String, CodingKey {
        case identifier, runtimeIdentifier, platformIdentifier, version, build, state, deletable, sizeBytes, lastUsedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try container.decodeIfPresent(String.self, forKey: .identifier)
        runtimeIdentifier = try container.decodeIfPresent(String.self, forKey: .runtimeIdentifier)
        platformIdentifier = try container.decodeIfPresent(String.self, forKey: .platformIdentifier)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        build = try container.decodeIfPresent(String.self, forKey: .build)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        // A missing flag means "not deletable": never offer an image simctl did not vouch for.
        deletable = try container.decodeIfPresent(Bool.self, forKey: .deletable) ?? false
        sizeBytes = try container.decodeIfPresent(Int64.self, forKey: .sizeBytes)
        lastUsedAt = try container.decodeIfPresent(String.self, forKey: .lastUsedAt)
    }
}

private struct RawDevicesResponse: Decodable {
    struct Device: Decodable {
        let state: String
    }

    let devices: [String: [Device]]
}
