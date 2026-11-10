import Foundation
import Testing
@testable import SimulatorCore
import SimulatorCoreTestSupport

@Suite("Mach-O entitlements reader")
struct MachOEntitlementsReaderTests {
    private static let groups = ["group.com.acme.notes", "group.com.acme.notes.shared"]
    private static var entitlements: [String: Any] {
        MachOFixture.entitlements(applicationIdentifier: "com.acme.notes", applicationGroups: groups)
    }

    @Test("Reads the app groups from a thin 64-bit executable's __TEXT,__entitlements")
    func readsThinExecutable() throws {
        let url = try Self.write(MachOFixture.thinExecutable(entitlements: Self.entitlements))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(MachOEntitlementsReader.applicationGroupIdentifiers(ofExecutableAt: url) == Set(Self.groups))
    }

    @Test("Entitlements without app groups are a known empty set, not unknown")
    func entitlementsWithoutGroupsAreEmpty() throws {
        let url = try Self.write(MachOFixture.thinExecutable(entitlements: ["application-identifier": "ABCDE12345.com.acme.notes"]))
        defer { try? FileManager.default.removeItem(at: url) }

        let groups = MachOEntitlementsReader.applicationGroupIdentifiers(ofExecutableAt: url)
        #expect(groups?.isEmpty == true)
    }

    @Test("An executable without an __entitlements section is unknown")
    func missingSectionIsUnknown() throws {
        let url = try Self.write(MachOFixture.thinExecutable(entitlements: nil))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(MachOEntitlementsReader.applicationGroupIdentifiers(ofExecutableAt: url) == nil)
    }

    @Test("A universal binary is read from whichever slice carries the section", arguments: [false, true])
    func readsFatExecutable(is64Bit: Bool) throws {
        // Host first or not, the slice without a section must not end the search.
        for slices in try [
            [
                (MachOFixture.cpuTypeX8664, MachOFixture.thinExecutable(entitlements: nil, cpuType: MachOFixture.cpuTypeX8664)),
                (MachOFixture.cpuTypeARM64, MachOFixture.thinExecutable(entitlements: Self.entitlements))
            ],
            [
                (MachOFixture.cpuTypeARM64, MachOFixture.thinExecutable(entitlements: nil)),
                (MachOFixture.cpuTypeX8664, MachOFixture.thinExecutable(entitlements: Self.entitlements,
                                                                        cpuType: MachOFixture.cpuTypeX8664))
            ]
        ] {
            let url = try Self.write(MachOFixture.fatExecutable(slices: slices.map { (cpuType: $0.0, image: $0.1) },
                                                                is64Bit: is64Bit))
            defer { try? FileManager.default.removeItem(at: url) }

            #expect(MachOEntitlementsReader.applicationGroupIdentifiers(ofExecutableAt: url) == Set(Self.groups))
        }
    }

    @Test("A universal binary whose slices have no section is unknown")
    func fatWithoutSectionIsUnknown() throws {
        let url = try Self.write(MachOFixture.fatExecutable(slices: [
            (cpuType: MachOFixture.cpuTypeARM64, image: MachOFixture.thinExecutable(entitlements: nil))
        ]))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(MachOEntitlementsReader.applicationGroupIdentifiers(ofExecutableAt: url) == nil)
    }

    @Test("Truncated executables are unknown, wherever they are cut")
    func truncatedIsUnknown() throws {
        let image = try MachOFixture.thinExecutable(entitlements: Self.entitlements)
        // Inside the header, inside the load commands, and inside the section itself.
        for length in [0, 3, 20, 100, image.count - 20] {
            let url = try Self.write(image.prefix(length))
            defer { try? FileManager.default.removeItem(at: url) }

            #expect(MachOEntitlementsReader.applicationGroupIdentifiers(ofExecutableAt: url) == nil, "cut at \(length)")
        }

        let fat = MachOFixture.fatExecutable(slices: [(cpuType: MachOFixture.cpuTypeARM64, image: image)])
        let url = try Self.write(fat.prefix(4096 + 50))
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(MachOEntitlementsReader.applicationGroupIdentifiers(ofExecutableAt: url) == nil)
    }

    @Test("Garbage, scripts, absurd headers and missing files are unknown")
    func garbageIsUnknown() throws {
        var absurdFatHeader = Data([0xCA, 0xFE, 0xBA, 0xBE, 0xFF, 0xFF, 0xFF, 0xFF])
        absurdFatHeader.append(Data(count: 64))
        var hugeLoadCommands = try MachOFixture.thinExecutable(entitlements: Self.entitlements)
        hugeLoadCommands.replaceSubrange(20 ..< 24, with: [0xFF, 0xFF, 0xFF, 0x7F])
        var oversizedCommand = try MachOFixture.thinExecutable(entitlements: Self.entitlements)
        oversizedCommand.replaceSubrange(36 ..< 40, with: [0xFF, 0xFF, 0x00, 0x00]) // __PAGEZERO's cmdsize

        for contents in [
            Data("#!/bin/sh\necho hello\n".utf8),
            Data((0 ..< 4096).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) }),
            absurdFatHeader,
            hugeLoadCommands,
            oversizedCommand
        ] {
            let url = try Self.write(contents)
            defer { try? FileManager.default.removeItem(at: url) }

            #expect(MachOEntitlementsReader.applicationGroupIdentifiers(ofExecutableAt: url) == nil)
        }

        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString)")
        #expect(MachOEntitlementsReader.applicationGroupIdentifiers(ofExecutableAt: missing) == nil)
    }

    @Test("A section that is not a property list, or groups that are not strings, are unknown")
    func malformedEntitlementsAreUnknown() throws {
        let notAPlist = Self.write(MachOFixture.thinExecutable(entitlementsSection: Data("not a plist".utf8)))
        let wrongType = try Self.write(MachOFixture.thinExecutable(entitlements: [
            "com.apple.security.application-groups": "group.com.acme.notes"
        ]))
        defer {
            try? FileManager.default.removeItem(at: notAPlist)
            try? FileManager.default.removeItem(at: wrongType)
        }

        #expect(MachOEntitlementsReader.applicationGroupIdentifiers(ofExecutableAt: notAPlist) == nil)
        #expect(MachOEntitlementsReader.applicationGroupIdentifiers(ofExecutableAt: wrongType) == nil)
    }

    private static func write(_ data: Data) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("macho-fixture-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: url.path, contents: data)
        return url
    }
}
