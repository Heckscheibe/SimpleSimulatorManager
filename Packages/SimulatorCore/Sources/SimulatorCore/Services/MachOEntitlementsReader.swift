//
//  MachOEntitlementsReader.swift
//  SimulatorManager
//

import Foundation
import os

/// Reads the entitlements a simulator build embeds in its main executable.
///
/// Xcode's simulator builds sign ad hoc, so the code signature carries no entitlements; the linker
/// writes them instead, as an XML property list, into the executable's `__TEXT,__entitlements`
/// section. There is no `.xcent` in the bundle and the container metadata says nothing about them,
/// so this section is the one place an app's real `com.apple.security.application-groups` can be
/// read.
///
/// Discovery calls this for every app on every load, so it reads only the Mach-O header, the load
/// commands and the section itself — a few kilobytes, whatever the size of the binary — and never
/// launches a process. Anything it does not understand (a 32-bit or big-endian slice, a truncated
/// or garbage file, a section that is not a property list) is "no entitlements": `nil`, logged, and
/// the caller falls back to what it did before entitlements could be read.
enum MachOEntitlementsReader {
    static let applicationGroupsKey = "com.apple.security.application-groups"

    /// The app groups `executableURL` is entitled to, or `nil` when its entitlements are unknown.
    ///
    /// An empty set is a real answer: the executable has entitlements and none of them is an app
    /// group, so the app cannot open any group container.
    static func applicationGroupIdentifiers(ofExecutableAt executableURL: URL) -> Set<String>? {
        guard let entitlements = entitlements(ofExecutableAt: executableURL) else {
            return nil
        }
        guard let value = entitlements[applicationGroupsKey] else {
            return []
        }
        guard let groups = value as? [String] else {
            os_log("Ignoring malformed \(applicationGroupsKey) entitlement in \(executableURL.path)")
            return nil
        }

        return Set(groups)
    }

    /// The executable's entitlements dictionary, or `nil` when it has none this reader can parse.
    static func entitlements(ofExecutableAt executableURL: URL) -> [String: Any]? {
        let data: Data
        do {
            let handle = try FileHandle(forReadingFrom: executableURL)
            defer { try? handle.close() }

            guard let sectionData = try MachOFile(handle: handle).entitlementsSection() else {
                return nil
            }

            data = sectionData
        } catch {
            os_log("Could not read entitlements of \(executableURL.path): \(String(describing: error))")
            return nil
        }

        // The linker may pad the section; the property list parser rejects trailing NULs.
        let plistData = Data(data.reversed().drop { $0 == 0 }.reversed())
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil),
              let entitlements = plist as? [String: Any] else {
            os_log("The entitlements section of \(executableURL.path) is not a property list dictionary")
            return nil
        }

        return entitlements
    }
}

enum MachOReadError: Error, Equatable {
    case truncated(offset: UInt64, count: Int)
    case malformed(String)
}

/// The bounded subset of the Mach-O format the reader needs: thin 64-bit little-endian images and
/// fat (universal) wrappers of them.
private struct MachOFile {
    // <mach-o/loader.h> and <mach-o/fat.h>
    static let machHeader64Magic: UInt32 = 0xFEED_FACF
    static let fatMagic: UInt32 = 0xCAFE_BABE
    static let fatMagic64: UInt32 = 0xCAFE_BABF
    static let loadCommandSegment64: UInt32 = 0x19
    static let machHeader64Size = 32
    static let segmentCommand64Size = 72
    static let section64Size = 80
    static let fatArchSize = 20
    static let fatArch64Size = 32
    static let cpuTypeARM64: UInt32 = 0x0100_000C
    static let cpuTypeX8664: UInt32 = 0x0100_0007

    // Caps that keep a hostile or corrupt file from making discovery read megabytes. Real
    // simulator executables have well under 100 KB of load commands and a section of a few KB.
    static let maxLoadCommandsSize = 4 * 1024 * 1024
    static let maxSectionSize = 1024 * 1024
    static let maxMachOSlices = 32

    #if arch(arm64)
        static let hostCPUType = cpuTypeARM64
    #else
        static let hostCPUType = cpuTypeX8664
    #endif

    let handle: FileHandle

    /// The raw `__TEXT,__entitlements` bytes, or `nil` when the executable has no such section or
    /// is not a Mach-O image this reader supports.
    func entitlementsSection() throws -> Data? {
        let fileSize = try handle.seekToEnd()
        let magicBytes = try read(at: 0, count: 4)

        if Self.uint32(littleEndian: magicBytes, at: 0) == Self.machHeader64Magic {
            return try entitlementsSection(inSliceAt: 0, size: fileSize)
        }

        switch Self.uint32(bigEndian: magicBytes, at: 0) {
        case Self.fatMagic:
            return try entitlementsSectionInFatFile(is64Bit: false, fileSize: fileSize)
        case Self.fatMagic64:
            return try entitlementsSectionInFatFile(is64Bit: true, fileSize: fileSize)
        default:
            // A 32-bit or big-endian image, a script, garbage: no entitlements this reader can see.
            return nil
        }
    }

    private func entitlementsSectionInFatFile(is64Bit: Bool, fileSize: UInt64) throws -> Data? {
        let header = try read(at: 0, count: 8)
        let sliceCount = Int(Self.uint32(bigEndian: header, at: 4))
        guard (1 ... Self.maxMachOSlices).contains(sliceCount) else {
            throw MachOReadError.malformed("fat header lists \(sliceCount) slices")
        }

        let entrySize = is64Bit ? Self.fatArch64Size : Self.fatArchSize
        let table = try read(at: 8, count: sliceCount * entrySize)
        let slices: [MachOSlice] = (0 ..< sliceCount).map { index in
            let base = index * entrySize
            let cpuType = Self.uint32(bigEndian: table, at: base)
            if is64Bit {
                return MachOSlice(cpuType: cpuType,
                                  offset: Self.uint64(bigEndian: table, at: base + 8),
                                  size: Self.uint64(bigEndian: table, at: base + 16))
            }
            return MachOSlice(cpuType: cpuType,
                              offset: UInt64(Self.uint32(bigEndian: table, at: base + 8)),
                              size: UInt64(Self.uint32(bigEndian: table, at: base + 12)))
        }

        // Every slice of one build carries the same entitlements; the host's is tried first only
        // because it is the one that actually runs.
        let ordered = slices.filter { $0.cpuType == Self.hostCPUType } + slices.filter { $0.cpuType != Self.hostCPUType }
        for slice in ordered {
            guard slice.offset <= fileSize, slice.size <= fileSize - slice.offset else {
                os_log("Skipping a fat slice that lies outside the file (offset \(slice.offset), size \(slice.size))")
                continue
            }

            do {
                if let section = try entitlementsSection(inSliceAt: slice.offset, size: slice.size) {
                    return section
                }
            } catch {
                os_log("Skipping an unreadable fat slice: \(String(describing: error))")
            }
        }

        return nil
    }

    private func entitlementsSection(inSliceAt sliceOffset: UInt64, size sliceSize: UInt64) throws -> Data? {
        guard sliceSize >= UInt64(Self.machHeader64Size) else {
            throw MachOReadError.malformed("slice of \(sliceSize) bytes is smaller than a Mach-O header")
        }

        let header = try read(at: sliceOffset, count: Self.machHeader64Size)
        guard Self.uint32(littleEndian: header, at: 0) == Self.machHeader64Magic else {
            return nil
        }

        let commandCount = Int(Self.uint32(littleEndian: header, at: 16))
        let commandsSize = Int(Self.uint32(littleEndian: header, at: 20))
        guard commandsSize <= Self.maxLoadCommandsSize,
              UInt64(Self.machHeader64Size + commandsSize) <= sliceSize else {
            throw MachOReadError.malformed("load commands of \(commandsSize) bytes do not fit the slice")
        }

        let commands = try read(at: sliceOffset + UInt64(Self.machHeader64Size), count: commandsSize)
        var cursor = 0
        for _ in 0 ..< commandCount {
            guard cursor + 8 <= commands.count else {
                throw MachOReadError.malformed("load command at \(cursor) runs past the load commands")
            }

            let command = Self.uint32(littleEndian: commands, at: cursor)
            let commandSize = Int(Self.uint32(littleEndian: commands, at: cursor + 4))
            guard commandSize >= 8, commandSize <= commands.count - cursor else {
                throw MachOReadError.malformed("load command at \(cursor) has size \(commandSize)")
            }

            if command == Self.loadCommandSegment64,
               commandSize >= Self.segmentCommand64Size,
               Self.name(in: commands, at: cursor + 8) == "__TEXT",
               let section = try entitlementsSection(inSegmentAt: cursor,
                                                     commandSize: commandSize,
                                                     commands: commands,
                                                     slice: MachOSlice(cpuType: 0, offset: sliceOffset, size: sliceSize)) {
                return section
            }
            cursor += commandSize
        }

        return nil
    }

    private func entitlementsSection(
        inSegmentAt segmentOffset: Int,
        commandSize: Int,
        commands: [UInt8],
        slice: MachOSlice
    ) throws -> Data? {
        let sectionCount = Int(Self.uint32(littleEndian: commands, at: segmentOffset + 64))
        guard sectionCount <= (commandSize - Self.segmentCommand64Size) / Self.section64Size else {
            throw MachOReadError.malformed("__TEXT lists \(sectionCount) sections in \(commandSize) bytes")
        }

        for index in 0 ..< sectionCount {
            let base = segmentOffset + Self.segmentCommand64Size + index * Self.section64Size
            guard Self.name(in: commands, at: base) == "__entitlements" else {
                continue
            }

            let size = Self.uint64(littleEndian: commands, at: base + 40)
            let offset = UInt64(Self.uint32(littleEndian: commands, at: base + 48))
            guard size <= UInt64(Self.maxSectionSize), offset <= slice.size, size <= slice.size - offset else {
                throw MachOReadError.malformed("__entitlements (offset \(offset), size \(size)) lies outside the slice")
            }

            return try Data(read(at: slice.offset + offset, count: Int(size)))
        }

        return nil
    }

    // MARK: - Reading

    /// Exactly `count` bytes at `offset`, or a throw — a short read means the file is truncated.
    private func read(at offset: UInt64, count: Int) throws -> [UInt8] {
        guard count > 0 else {
            return []
        }

        try handle.seek(toOffset: offset)
        guard let data = try handle.read(upToCount: count), data.count == count else {
            throw MachOReadError.truncated(offset: offset, count: count)
        }

        return [UInt8](data)
    }

    private static func uint32(littleEndian bytes: [UInt8], at offset: Int) -> UInt32 {
        (0 ..< 4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << (8 * $1) }
    }

    private static func uint32(bigEndian bytes: [UInt8], at offset: Int) -> UInt32 {
        (0 ..< 4).reduce(UInt32(0)) { $0 << 8 | UInt32(bytes[offset + $1]) }
    }

    private static func uint64(littleEndian bytes: [UInt8], at offset: Int) -> UInt64 {
        (0 ..< 8).reduce(UInt64(0)) { $0 | UInt64(bytes[offset + $1]) << (8 * $1) }
    }

    private static func uint64(bigEndian bytes: [UInt8], at offset: Int) -> UInt64 {
        (0 ..< 8).reduce(UInt64(0)) { $0 << 8 | UInt64(bytes[offset + $1]) }
    }

    /// A fixed 16-byte, NUL-padded segment or section name.
    private static func name(in bytes: [UInt8], at offset: Int) -> String {
        let field = bytes[offset ..< offset + 16]
        return String(decoding: field.prefix { $0 != 0 }, as: UTF8.self)
    }
}

/// Where one architecture's image sits in the file; a thin file is a single slice at offset 0.
private struct MachOSlice {
    let cpuType: UInt32
    let offset: UInt64
    let size: UInt64
}
