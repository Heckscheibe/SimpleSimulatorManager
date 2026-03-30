import Foundation
import Testing
@testable import SimulatorManager

@Suite("SimulatorCleanupService Tests")
struct SimulatorCleanupServiceTests {
    @Test("Unavailable devices with missing runtimes become simctl cleanup candidates")
    func unavailableDeviceWithMissingRuntime() {
        let directoryRecord = SimulatorDirectoryRecord(
            udid: "E95A4AE1-04A0-4C9B-8CF2-EDDD2F6CE053",
            directoryURL: URL(fileURLWithPath: "/tmp/E95A4AE1-04A0-4C9B-8CF2-EDDD2F6CE053"),
            metadataStatus: .decoded(
                SimulatorDirectoryMetadata(
                    udid: "E95A4AE1-04A0-4C9B-8CF2-EDDD2F6CE053",
                    name: "iPhone 16 Pro",
                    runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-1",
                    deviceTypeIdentifier: "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro",
                    lastBootedAt: nil
                )
            )
        )

        let candidates = SimulatorCleanupService.buildCleanupCandidates(
            simctlDevices: [
                SimctlDeviceRecord(
                    udid: "E95A4AE1-04A0-4C9B-8CF2-EDDD2F6CE053",
                    name: "iPhone 16 Pro",
                    state: "Shutdown",
                    runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-1",
                    deviceTypeIdentifier: "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro",
                    dataPath: nil,
                    dataPathSize: 8192,
                    isAvailable: false,
                    availabilityError: "runtime profile not found using \"System\" match policy"
                )
            ],
            availableRuntimeIdentifiers: ["com.apple.CoreSimulator.SimRuntime.iOS-18-5"],
            directoryRecords: [directoryRecord]
        )

        #expect(candidates.count == 1)
        #expect(candidates[0].reasons.contains(.missingRuntime))
        #expect(candidates[0].reasons.contains(.unavailable))
        #expect(candidates[0].diskUsageBytes == 8192)

        if case let .simctlDelete(udid) = candidates[0].deletionMethod {
            #expect(udid == "E95A4AE1-04A0-4C9B-8CF2-EDDD2F6CE053")
        } else {
            Issue.record("Expected a simctl deletion candidate")
        }
    }

    @Test("Unreadable orphaned device directories become filesystem cleanup candidates")
    func unreadableOrphanedDirectory() {
        let directoryURL = URL(fileURLWithPath: "/tmp/5D91F5D6-6D4A-4D94-8B44-2926AE8E7C10")
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let payloadURL = directoryURL.appendingPathComponent("payload.bin")
        FileManager.default.createFile(atPath: payloadURL.path, contents: Data(repeating: 0, count: 2048))

        let candidates = SimulatorCleanupService.buildCleanupCandidates(
            simctlDevices: [],
            availableRuntimeIdentifiers: [],
            directoryRecords: [
                SimulatorDirectoryRecord(
                    udid: "5D91F5D6-6D4A-4D94-8B44-2926AE8E7C10",
                    directoryURL: directoryURL,
                    metadataStatus: .unreadableDevicePlist
                )
            ]
        )

        #expect(candidates.count == 1)
        #expect(candidates[0].reasons.contains(.orphanedDirectory))
        #expect(candidates[0].reasons.contains(.unreadableDeviceMetadata))
        #expect((candidates[0].diskUsageBytes ?? 0) >= 2048)

        if case let .trashDirectory(url) = candidates[0].deletionMethod {
            #expect(url == directoryURL)
        } else {
            Issue.record("Expected a filesystem deletion candidate")
        }

        try? FileManager.default.removeItem(at: directoryURL)
    }

    @Test("Duplicate directory UDIDs are ignored after the first record")
    func duplicateDirectoryUDIDsUseFirstRecord() {
        let directoryURL = URL(fileURLWithPath: "/tmp/E95A4AE1-04A0-4C9B-8CF2-EDDD2F6CE053")
        let firstRecord = SimulatorDirectoryRecord(
            udid: "E95A4AE1-04A0-4C9B-8CF2-EDDD2F6CE053",
            directoryURL: directoryURL,
            metadataStatus: .missingDevicePlist
        )
        let secondRecord = SimulatorDirectoryRecord(
            udid: "E95A4AE1-04A0-4C9B-8CF2-EDDD2F6CE053",
            directoryURL: directoryURL,
            metadataStatus: .unreadableDevicePlist
        )

        let candidates = SimulatorCleanupService.buildCleanupCandidates(
            simctlDevices: [
                SimctlDeviceRecord(
                    udid: "E95A4AE1-04A0-4C9B-8CF2-EDDD2F6CE053",
                    name: "iPhone 16 Pro",
                    state: "Shutdown",
                    runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-1",
                    deviceTypeIdentifier: "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro",
                    dataPath: nil,
                    dataPathSize: 8192,
                    isAvailable: false,
                    availabilityError: "runtime profile not found using \"System\" match policy"
                )
            ],
            availableRuntimeIdentifiers: [],
            directoryRecords: [firstRecord, secondRecord]
        )

        #expect(candidates.count == 1)
        #expect(candidates[0].reasons.contains(.missingDevicePlist))
        #expect(!candidates[0].reasons.contains(.unreadableDeviceMetadata))
    }
}
