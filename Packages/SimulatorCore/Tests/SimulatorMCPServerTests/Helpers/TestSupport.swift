import Foundation
import MCP
import SimulatorCore
import SimulatorCoreTestSupport
@testable import SimulatorMCPServer

/// Known identifiers of the sample simulators ``SampleSimulators`` writes.
enum Sample {
    static let iPhoneUdid = "11111111-1111-1111-1111-111111111111"
    static let iPadUdid = "22222222-2222-2222-2222-222222222222"
    static let watchUdid = "33333333-3333-3333-3333-333333333333"
    static let unknownUdid = "99999999-9999-9999-9999-999999999999"

    static let appBundleId = "com.example.notes"
    static let otherAppBundleId = "com.example.weather"
    static let appGroupId = "group.com.example.notes"
    static let suiteDomain = "com.example.notes.shared"

    static let lastBootedAt = Date(timeIntervalSince1970: 1_760_000_000)
    static let olderChange = Date(timeIntervalSince1970: 1_750_000_000)
    static let newerChange = Date(timeIntervalSince1970: 1_755_000_000)
}

/// A fixture devices directory populated with a booted iPhone holding two apps and an app group,
/// an iPad holding one of those apps, and an empty watch.
struct SampleSimulators {
    let fixture: DeviceFixtureDirectory
    let notesOnIPhone: DeviceFixtureDirectory.InstalledApp
    let appGroupURL: URL

    init() throws {
        fixture = try DeviceFixtureDirectory()

        try fixture.writeDevice(udid: Sample.iPhoneUdid, name: "iPhone 16 Pro", state: .running, lastBootedAt: Sample.lastBootedAt)
        try fixture.writeDevice(udid: Sample.iPadUdid, name: "iPad Air", deviceTypeIdentifier: DeviceFixtureDirectory.DeviceTypeIdentifier.iPad)
        try fixture.writeDevice(udid: Sample.watchUdid,
                                name: "Apple Watch",
                                deviceTypeIdentifier: DeviceFixtureDirectory.DeviceTypeIdentifier.watch,
                                runtime: "com.apple.CoreSimulator.SimRuntime.watchOS-26-0")

        notesOnIPhone = try fixture.writeApp(
            bundleIdentifier: Sample.appBundleId,
            name: "Notes",
            onDeviceWithUdid: Sample.iPhoneUdid,
            userDefaults: [
                Sample.appBundleId: ["token": "abc", "launchCount": 3],
                Sample.suiteDomain: ["shared": true],
                "com.apple.UIKit": ["system": 1]
            ],
            modifiedAt: Sample.newerChange
        )
        try fixture.writeApp(bundleIdentifier: Sample.otherAppBundleId,
                             name: "Weather",
                             onDeviceWithUdid: Sample.iPhoneUdid,
                             modifiedAt: Sample.olderChange)
        try fixture.writeApp(bundleIdentifier: Sample.appBundleId,
                             name: "Notes",
                             onDeviceWithUdid: Sample.iPadUdid,
                             modifiedAt: Sample.olderChange)
        appGroupURL = try fixture.writeAppGroup(identifier: Sample.appGroupId,
                                                onDeviceWithUdid: Sample.iPhoneUdid,
                                                userDefaults: [Sample.appGroupId: ["groupValue": "x"]])
    }

    func remove() {
        fixture.remove()
    }

    func service(
        resetService: MockSimulatorResetService = MockSimulatorResetService(),
        cleanupService: MockSimulatorCleanupService = MockSimulatorCleanupService()
    ) -> SimulatorQueryService {
        SimulatorQueryService(deviceLoader: DeviceLoader(devicesDirectoryURL: fixture.url),
                              resetService: resetService,
                              cleanupService: cleanupService)
    }

    func registry(
        _ options: ServerOptions = ServerOptions(),
        resetService: MockSimulatorResetService = MockSimulatorResetService(),
        cleanupService: MockSimulatorCleanupService = MockSimulatorCleanupService()
    ) -> ToolRegistry {
        ToolRegistry(options: options, service: service(resetService: resetService, cleanupService: cleanupService))
    }
}

extension ServerOptions {
    static let allFlags = ServerOptions(allowUserDefaults: true, allowDestructive: true, allowSnapshots: true)
}

enum CleanupCandidateFactory {
    static func simctlCandidate(udid: String = "44444444-4444-4444-4444-444444444444") -> SimulatorCleanupCandidate {
        SimulatorCleanupCandidate(id: "simctl-\(udid)",
                                  name: "iPhone 12",
                                  udid: udid,
                                  simulatorPlatform: .iPhone,
                                  osVersion: "iOS 15.0",
                                  lastBootedAt: Sample.lastBootedAt,
                                  diskUsageBytes: 2048,
                                  reasons: [.unavailable, .missingRuntime],
                                  detailMessage: "runtime profile not found",
                                  deletionMethod: .simctlDelete(udid))
    }

    static func directoryCandidate() -> SimulatorCleanupCandidate {
        SimulatorCleanupCandidate(id: "directory-ABC",
                                  name: "ABC",
                                  udid: nil,
                                  simulatorPlatform: nil,
                                  osVersion: nil,
                                  lastBootedAt: nil,
                                  diskUsageBytes: nil,
                                  reasons: [.orphanedDirectory],
                                  detailMessage: nil,
                                  deletionMethod: .trashDirectory(URL(fileURLWithPath: "/tmp/Devices/ABC")))
    }
}

extension CallTool.Result {
    var text: String {
        let texts = content.compactMap { content -> String? in
            guard case let .text(text, _, _) = content else {
                return nil
            }

            return text
        }
        return texts.joined()
    }

    var failed: Bool {
        isError == true
    }

    /// The text content parsed as a JSON object.
    func json() throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8))
        guard let dictionary = object as? [String: Any] else {
            throw MockServiceError()
        }

        return dictionary
    }
}
