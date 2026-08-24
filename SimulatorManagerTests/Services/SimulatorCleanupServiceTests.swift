import Foundation
import Testing
@testable import SimulatorManager

@Suite("SimulatorCleanupService Tests")
struct SimulatorCleanupServiceTests {
    @Test("Unavailable devices with missing runtimes become simctl cleanup candidates")
    func unavailableDeviceWithMissingRuntime() throws {
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

        try #require(candidates.count == 1)
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
    func unreadableOrphanedDirectory() throws {
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

        try #require(candidates.count == 1)
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

    @Test("Unavailable devices without a corroborating failure are not offered for deletion")
    func unavailableDeviceWithoutCorroboratingFailureIsSkipped() {
        // A runtime that is still downloading leaves its devices unavailable with no missing
        // runtime, missing device type or broken metadata. Those recover on their own, and
        // simctl deletion is irreversible, so they must not show up as candidates.
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
                    availabilityError: nil
                )
            ],
            availableRuntimeIdentifiers: ["com.apple.CoreSimulator.SimRuntime.iOS-26-1"],
            directoryRecords: [
                SimulatorDirectoryRecord(
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
            ]
        )

        #expect(candidates.isEmpty)
    }

    @Test("Unavailable devices with a missing device type stay cleanup candidates")
    func unavailableDeviceWithMissingDeviceType() throws {
        // The runtime is installed, so only the device type profile is gone. That is a hard
        // failure and still qualifies, using the exact wording CoreSimulator reports.
        let candidates = SimulatorCleanupService.buildCleanupCandidates(
            simctlDevices: [
                SimctlDeviceRecord(
                    udid: "E95A4AE1-04A0-4C9B-8CF2-EDDD2F6CE053",
                    name: "iPhone 16 Pro",
                    state: "Shutdown",
                    runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-1",
                    deviceTypeIdentifier: "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro",
                    dataPath: nil,
                    dataPathSize: 4096,
                    isAvailable: false,
                    availabilityError: "device type profile not found"
                )
            ],
            availableRuntimeIdentifiers: ["com.apple.CoreSimulator.SimRuntime.iOS-26-1"],
            directoryRecords: []
        )

        try #require(candidates.count == 1)
        #expect(candidates[0].reasons.contains(.missingDeviceType))
        #expect(!candidates[0].reasons.contains(.missingRuntime))
    }

    @Test("Unavailable devices with broken directory metadata stay cleanup candidates")
    func unavailableDeviceWithBrokenMetadata() throws {
        let candidates = SimulatorCleanupService.buildCleanupCandidates(
            simctlDevices: [
                SimctlDeviceRecord(
                    udid: "E95A4AE1-04A0-4C9B-8CF2-EDDD2F6CE053",
                    name: "iPhone 16 Pro",
                    state: "Shutdown",
                    runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-1",
                    deviceTypeIdentifier: "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro",
                    dataPath: nil,
                    dataPathSize: 4096,
                    isAvailable: false,
                    availabilityError: nil
                )
            ],
            availableRuntimeIdentifiers: ["com.apple.CoreSimulator.SimRuntime.iOS-26-1"],
            directoryRecords: [
                SimulatorDirectoryRecord(
                    udid: "E95A4AE1-04A0-4C9B-8CF2-EDDD2F6CE053",
                    directoryURL: URL(fileURLWithPath: "/tmp/E95A4AE1-04A0-4C9B-8CF2-EDDD2F6CE053"),
                    metadataStatus: .missingDevicePlist
                )
            ]
        )

        try #require(candidates.count == 1)
        #expect(candidates[0].reasons.contains(.missingDevicePlist))
    }

    @Test("Duplicate orphaned directory UDIDs produce a single candidate")
    func duplicateOrphanedDirectoryUDIDsProduceOneCandidate() throws {
        // Two directories claiming the same UDID (a copied simulator folder) must not both become
        // an `orphan-<udid>` candidate: identical IDs collide in the SwiftUI ForEach that renders
        // the cleanup menu.
        let udid = "5D91F5D6-6D4A-4D94-8B44-2926AE8E7C10"
        let candidates = SimulatorCleanupService.buildCleanupCandidates(
            simctlDevices: [],
            availableRuntimeIdentifiers: [],
            directoryRecords: [
                SimulatorDirectoryRecord(
                    udid: udid,
                    directoryURL: URL(fileURLWithPath: "/tmp/\(udid)"),
                    metadataStatus: .missingDevicePlist
                ),
                SimulatorDirectoryRecord(
                    udid: udid,
                    directoryURL: URL(fileURLWithPath: "/tmp/copy-of-\(udid)"),
                    metadataStatus: .unreadableDevicePlist
                )
            ],
            directorySizeProvider: { _ in 1024 }
        )

        try #require(candidates.count == 1)
        #expect(Set(candidates.map(\.id)).count == candidates.count)
        #expect(candidates[0].id == "orphan-\(udid)")
        #expect(candidates[0].reasons.contains(.missingDevicePlist))
    }

    @Test("device.plist UDID is decoded from the uppercase key")
    func devicePlistUDIDIsDecodedFromUppercaseKey() throws {
        // Real device.plist files spell the key `UDID`; a lowercase mapping silently decodes nil
        // and falls back to the folder name.
        let folderName = "5D91F5D6-6D4A-4D94-8B44-2926AE8E7C10"
        let plistUDID = "E95A4AE1-04A0-4C9B-8CF2-EDDD2F6CE053"
        let directoryURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("cleanup-plist-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL.deletingLastPathComponent()) }

        let plist: [String: Any] = [
            "UDID": plistUDID,
            "name": "iPhone 16 Pro",
            "runtime": "com.apple.CoreSimulator.SimRuntime.iOS-26-1",
            "deviceType": "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: directoryURL.appendingPathComponent(SimulatorPaths.devicePlistName))

        let record = try #require(SimulatorCleanupService.makeDirectoryRecord(for: directoryURL))

        #expect(record.udid == plistUDID)
        #expect(record.metadata?.name == "iPhone 16 Pro")
        #expect(record.metadata?.osVersion == "iOS 26.1")
    }

    @Test("Directory sizing reports an unknown size instead of a truncated one at the entry limit")
    func directorySizingStopsAtEntryLimit() throws {
        let directoryURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("cleanup-size-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        for index in 0 ..< 5 {
            FileManager.default.createFile(
                atPath: directoryURL.appendingPathComponent("file-\(index).bin").path,
                contents: Data(repeating: 0, count: 1024)
            )
        }

        // Within the limit the real total is reported; past it the size is unknown rather than a
        // silently short number shown to someone deciding what to delete.
        #expect(SimulatorCleanupService.calculateDirectorySize(at: directoryURL, entryLimit: 10) != nil)
        #expect(SimulatorCleanupService.calculateDirectorySize(at: directoryURL, entryLimit: 2) == nil)
    }

    @Test("Directory sizing counts hidden files")
    func directorySizingCountsHiddenFiles() throws {
        // Simulator containers hold a lot of their bytes in dotfiles and hidden caches, so skipping
        // hidden entries understated the total someone uses to decide what is worth deleting.
        let rootURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("cleanup-hidden-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let visibleOnlyURL = rootURL.appendingPathComponent("visible-only", isDirectory: true)
        let withHiddenURL = rootURL.appendingPathComponent("with-hidden", isDirectory: true)
        try FileManager.default.createDirectory(at: visibleOnlyURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: withHiddenURL, withIntermediateDirectories: true)

        for directoryURL in [visibleOnlyURL, withHiddenURL] {
            FileManager.default.createFile(
                atPath: directoryURL.appendingPathComponent("visible.bin").path,
                contents: Data(repeating: 0, count: 4096)
            )
        }

        FileManager.default.createFile(
            atPath: withHiddenURL.appendingPathComponent(".hidden.bin").path,
            contents: Data(repeating: 0, count: 4096)
        )

        // Compared against the same tree without the dotfile rather than against a fixed number,
        // so the assertion does not depend on the filesystem's allocation block size.
        let visibleOnlySize = try #require(SimulatorCleanupService.calculateDirectorySize(at: visibleOnlyURL))
        let withHiddenSize = try #require(SimulatorCleanupService.calculateDirectorySize(at: withHiddenURL))

        #expect(withHiddenSize > visibleOnlySize)
    }

    @Test("Directory sizing reports an unknown size when part of the tree cannot be read")
    func directorySizingReportsUnknownWhenEnumerationFails() throws {
        let directoryURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("cleanup-unreadable-\(UUID().uuidString)", isDirectory: true)
        let unreadableURL = directoryURL.appendingPathComponent("unreadable", isDirectory: true)
        try FileManager.default.createDirectory(at: unreadableURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: unreadableURL.path)
            try? FileManager.default.removeItem(at: directoryURL)
        }

        FileManager.default.createFile(
            atPath: unreadableURL.appendingPathComponent("hidden-away.bin").path,
            contents: Data(repeating: 0, count: 4096)
        )
        FileManager.default.createFile(
            atPath: directoryURL.appendingPathComponent("visible.bin").path,
            contents: Data(repeating: 0, count: 4096)
        )

        // Strip the search bit so the walk cannot descend, which is what the error handler sees.
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadableURL.path)

        // A partial total would understate the simulator and is worse than admitting we don't know.
        #expect(SimulatorCleanupService.calculateDirectorySize(at: directoryURL) == nil)
    }

    @Test("Duplicate directory UDIDs are ignored after the first record")
    func duplicateDirectoryUDIDsUseFirstRecord() throws {
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

        try #require(candidates.count == 1)
        #expect(candidates[0].reasons.contains(.missingDevicePlist))
        #expect(!candidates[0].reasons.contains(.unreadableDeviceMetadata))
    }
}
