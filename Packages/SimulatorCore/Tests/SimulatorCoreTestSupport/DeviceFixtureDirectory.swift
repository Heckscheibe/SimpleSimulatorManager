import Foundation
import SimulatorCore

/// A throwaway CoreSimulator `Devices` directory holding hand-written plist fixtures, laid out the
/// way CoreSimulator writes it, so loading can be exercised against known devices, apps, app groups
/// and UserDefaults instead of the machine's own simulators.
///
/// Shared by every test target in this package, and compiled into the app's test target as well,
/// so there is one fixture writer for both.
public struct DeviceFixtureDirectory {
    public enum DeviceTypeIdentifier {
        public static let iPhone = "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro"
        public static let iPad = "com.apple.CoreSimulator.SimDeviceType.iPad-Air-11-inch-M3"
        public static let watch = "com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-10-46mm"
    }

    /// Paths of an installed app, for asserting what loading reports.
    public struct InstalledApp {
        public let dataContainerURL: URL
        public let bundleURL: URL
    }

    public let url: URL

    public init() throws {
        let temporaryURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("simulator-core-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryURL, withIntermediateDirectories: true)

        // Directory enumeration reports `/private/var/…` for the temporary directory's `/var/…`, so
        // the fixture uses the real path for its expectations to compare equal to loaded paths.
        // `resolvingSymlinksInPath()` would strip `/private` again, hence `realpath`.
        guard let realPath = realpath(temporaryURL.path, nil) else {
            throw CocoaError(.fileNoSuchFile)
        }

        defer { free(realPath) }
        url = URL(fileURLWithPath: String(cString: realPath), isDirectory: true)
    }

    public func remove() {
        try? FileManager.default.removeItem(at: url)
    }

    public func removeDevice(udid: String) {
        try? FileManager.default.removeItem(at: deviceURL(udid: udid))
    }

    public func deviceURL(udid: String) -> URL {
        url.appendingPathComponent(udid, isDirectory: true)
    }

    /// Writes the same keys a real `device.plist` carries, including the uppercase `UDID`.
    public func writeDevice(
        udid: String,
        name: String,
        deviceTypeIdentifier: String = DeviceTypeIdentifier.iPhone,
        runtime: String = "com.apple.CoreSimulator.SimRuntime.iOS-26-1",
        state: DeviceState = .off,
        lastBootedAt: Date? = nil
    ) throws {
        var plist: [String: Any] = [
            "UDID": udid,
            "name": name,
            "runtime": runtime,
            "deviceType": deviceTypeIdentifier,
            "state": state.rawValue
        ]
        plist["lastBootedAt"] = lastBootedAt
        try write(plist, to: deviceURL(udid: udid).appendingPathComponent(SimulatorPaths.devicePlistName))
    }

    /// A device folder whose `device.plist` is missing entirely.
    public func writeDeviceFolderWithoutPlist(udid: String) throws {
        try FileManager.default.createDirectory(at: deviceURL(udid: udid), withIntermediateDirectories: true)
    }

    /// A device folder whose `device.plist` is not a property list.
    public func writeDeviceWithUnreadablePlist(udid: String) throws {
        let folder = deviceURL(udid: udid)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not a plist".utf8).write(to: folder.appendingPathComponent(SimulatorPaths.devicePlistName))
    }

    /// Installs an iOS app: an `.app` bundle under `Containers/Bundle/Application` and a data
    /// container under `Containers/Data/Application`, tied together by the metadata identifier.
    /// Every entry of `userDefaults` becomes `Library/Preferences/<domain>.plist`.
    ///
    /// With `applicationGroupsEntitlement`, the bundle also gets a main executable whose
    /// `__TEXT,__entitlements` section lists those app groups, as a simulator build's does; without
    /// it the bundle has no executable, so discovery cannot read the app's entitlements.
    @discardableResult
    public func writeApp(
        bundleIdentifier: String,
        name: String,
        onDeviceWithUdid udid: String,
        userDefaults: [String: [String: Any]] = [:],
        modifiedAt: Date? = nil,
        bundleModifiedAt: Date? = nil,
        containerModifiedAt: Date? = nil,
        additionalInfoPlistEntries: [String: Any] = [:],
        applicationGroupsEntitlement: [String]? = nil
    ) throws -> InstalledApp {
        let dataFolder = deviceURL(udid: udid).appendingPathComponent(SimulatorPaths.dataFolderName)

        let bundleURL = dataFolder
            .appendingPathComponent(SimulatorPaths.appBundleApplicationsPath)
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("\(name).app")
        var infoPlist: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleName": name,
            "DTPlatformName": "iphonesimulator"
        ]
        if let applicationGroupsEntitlement {
            infoPlist["CFBundleExecutable"] = name
        }
        try write(infoPlist.merging(additionalInfoPlistEntries) { _, additional in additional },
                  to: bundleURL.appendingPathComponent(Self.infoPlistFileName))
        if let applicationGroupsEntitlement {
            let entitlements = MachOFixture.entitlements(applicationIdentifier: bundleIdentifier,
                                                         applicationGroups: applicationGroupsEntitlement)
            try MachOFixture.thinExecutable(entitlements: entitlements)
                .write(to: bundleURL.appendingPathComponent(name))
        }

        let containerURL = dataFolder
            .appendingPathComponent(SimulatorPaths.appDataApplicationsPath)
            .appendingPathComponent(UUID().uuidString)
        try write(["MCMMetadataIdentifier": bundleIdentifier], to: containerURL.appendingPathComponent(Self.metadataFileName))
        try writePreferences(userDefaults, inContainerAt: containerURL)

        // `modifiedAt` sets both; the specific dates win, so a test can model an app that has been
        // running (container touched) without having been reinstalled (bundle untouched).
        if let containerDate = containerModifiedAt ?? modifiedAt {
            try setModificationDate(containerDate, of: containerURL)
        }
        if let bundleDate = bundleModifiedAt ?? modifiedAt {
            try setModificationDate(bundleDate, of: bundleURL)
        }

        return InstalledApp(dataContainerURL: containerURL, bundleURL: bundleURL)
    }

    /// Writes an app group's shared container. Discovery only keeps a group that belongs to an
    /// installed app: one whose `applicationGroupsEntitlement` lists it, or — for an app written
    /// without one — whose bundle identifier is the group's name (the identifier after `group.`)
    /// or extends it by a dot-separated suffix.
    @discardableResult
    public func writeAppGroup(
        identifier: String,
        onDeviceWithUdid udid: String,
        userDefaults: [String: [String: Any]] = [:]
    ) throws -> URL {
        let uuid = UUID().uuidString
        let groupURL = deviceURL(udid: udid)
            .appendingPathComponent(SimulatorPaths.appGroupsPath)
            .appendingPathComponent(uuid)
        try write(["MCMMetadataIdentifier": identifier, "MCMMetadataUUID": uuid],
                  to: groupURL.appendingPathComponent(Self.metadataFileName))
        try writePreferences(userDefaults, inContainerAt: groupURL)

        return groupURL
    }

    public func writeDSStore() throws {
        try Data().write(to: url.appendingPathComponent(".DS_Store"))
    }

    // The same names CoreSimulator uses; spelled out because SimulatorCore keeps its own internal.
    private static let infoPlistFileName = "Info.plist"
    private static let metadataFileName = ".com.apple.mobile_container_manager.metadata.plist"

    private func writePreferences(_ userDefaults: [String: [String: Any]], inContainerAt containerURL: URL) throws {
        for (domain, values) in userDefaults {
            try write(values, to: containerURL
                .appendingPathComponent(SimulatorPaths.userDefaultsPath)
                .appendingPathComponent("\(domain).plist"))
        }
    }

    private func setModificationDate(_ date: Date, of url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    private func write(_ plist: [String: Any], to fileURL: URL) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: fileURL)
    }
}

/// Builds minimal Mach-O executables the way a simulator build lays out the parts the entitlements
/// reader looks at: a 64-bit little-endian header, a `__PAGEZERO` segment and an unrelated load
/// command to step over, and a `__TEXT` segment whose sections may include `__entitlements`.
/// Everything else a real binary has is left out, since nothing reads it.
public enum MachOFixture {
    public static let cpuTypeARM64: UInt32 = 0x0100_000C
    public static let cpuTypeX8664: UInt32 = 0x0100_0007

    public static func entitlements(applicationIdentifier: String, applicationGroups: [String]) -> [String: Any] {
        [
            "application-identifier": "ABCDE12345.\(applicationIdentifier)",
            "com.apple.security.application-groups": applicationGroups
        ]
    }

    /// A thin executable whose `__TEXT,__entitlements` holds `entitlements` as an XML property
    /// list, NUL-padded as the linker leaves it; `nil` leaves the section out.
    public static func thinExecutable(entitlements: [String: Any]?, cpuType: UInt32 = cpuTypeARM64) throws -> Data {
        let section = try entitlements.map {
            try PropertyListSerialization.data(fromPropertyList: $0, format: .xml, options: 0) + Data(count: 3)
        }
        return thinExecutable(entitlementsSection: section, cpuType: cpuType)
    }

    /// A thin executable whose `__TEXT,__entitlements` section holds `entitlementsSection` verbatim.
    public static func thinExecutable(entitlementsSection: Data?, cpuType: UInt32 = cpuTypeARM64) -> Data {
        let headerSize = 32
        let segmentSize = 72
        let sectionSize = 80
        let uuidCommandSize = 24
        let textSectionCount = entitlementsSection == nil ? 1 : 2
        let commandsSize = segmentSize + uuidCommandSize + segmentSize + textSectionCount * sectionSize
        let codeOffset = headerSize + commandsSize
        let code = Data([0xC0, 0x03, 0x5F, 0xD6]) // ret
        let entitlementsOffset = codeOffset + code.count

        var data = Data()
        // mach_header_64
        data.appendLittleEndian(UInt32(0xFEED_FACF))
        data.appendLittleEndian(cpuType)
        data.appendLittleEndian(UInt32(0)) // cpusubtype
        data.appendLittleEndian(UInt32(2)) // MH_EXECUTE
        data.appendLittleEndian(UInt32(3)) // ncmds
        data.appendLittleEndian(UInt32(commandsSize))
        data.appendLittleEndian(UInt32(0)) // flags
        data.appendLittleEndian(UInt32(0)) // reserved

        appendSegment(named: "__PAGEZERO", sectionCount: 0, to: &data)

        // LC_UUID, which the reader must step over by its size.
        data.appendLittleEndian(UInt32(0x1B))
        data.appendLittleEndian(UInt32(uuidCommandSize))
        data.append(Data(repeating: 0xAB, count: 16))

        appendSegment(named: "__TEXT", sectionCount: textSectionCount, to: &data)
        appendSection(named: "__text", offset: codeOffset, size: code.count, to: &data)
        if let entitlementsSection {
            appendSection(named: "__entitlements", offset: entitlementsOffset, size: entitlementsSection.count, to: &data)
        }

        data.append(code)
        data.append(entitlementsSection ?? Data())
        return data
    }

    /// A universal binary holding `slices`, each with its CPU type, behind a `fat_header`
    /// (`FAT_MAGIC`) or, with `is64Bit`, a `FAT_MAGIC_64` one.
    public static func fatExecutable(slices: [(cpuType: UInt32, image: Data)], is64Bit: Bool = false) -> Data {
        let alignment = 4096
        let entrySize = is64Bit ? 32 : 20
        var offset = alignment
        var header = Data()
        var body = Data(count: alignment - 8 - slices.count * entrySize)

        header.appendBigEndian(is64Bit ? UInt32(0xCAFE_BABF) : UInt32(0xCAFE_BABE))
        header.appendBigEndian(UInt32(slices.count))
        for slice in slices {
            header.appendBigEndian(slice.cpuType)
            header.appendBigEndian(UInt32(0)) // cpusubtype
            if is64Bit {
                header.appendBigEndian(UInt64(offset))
                header.appendBigEndian(UInt64(slice.image.count))
                header.appendBigEndian(UInt32(12)) // align, as a power of two
                header.appendBigEndian(UInt32(0)) // reserved
            } else {
                header.appendBigEndian(UInt32(offset))
                header.appendBigEndian(UInt32(slice.image.count))
                header.appendBigEndian(UInt32(12))
            }

            let padded = (slice.image.count + alignment - 1) / alignment * alignment
            body.append(slice.image)
            body.append(Data(count: padded - slice.image.count))
            offset += padded
        }

        return header + body
    }

    private static func appendSegment(named name: String, sectionCount: Int, to data: inout Data) {
        data.appendLittleEndian(UInt32(0x19)) // LC_SEGMENT_64
        data.appendLittleEndian(UInt32(72 + sectionCount * 80))
        data.appendName(name)
        data.append(Data(count: 32)) // vmaddr, vmsize, fileoff, filesize
        data.appendLittleEndian(UInt32(5)) // maxprot
        data.appendLittleEndian(UInt32(5)) // initprot
        data.appendLittleEndian(UInt32(sectionCount))
        data.appendLittleEndian(UInt32(0)) // flags
    }

    private static func appendSection(named name: String, offset: Int, size: Int, to data: inout Data) {
        data.appendName(name)
        data.appendName("__TEXT")
        data.appendLittleEndian(UInt64(0x1_0000_0000 + offset)) // addr
        data.appendLittleEndian(UInt64(size))
        data.appendLittleEndian(UInt32(offset))
        data.append(Data(count: 28)) // align, reloff, nreloc, flags, reserved1-3
    }
}

private extension Data {
    mutating func appendLittleEndian(_ value: some FixedWidthInteger) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendBigEndian(_ value: some FixedWidthInteger) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }

    /// A segment or section name: 16 bytes, NUL-padded.
    mutating func appendName(_ name: String) {
        let bytes = Array(name.utf8.prefix(16))
        append(contentsOf: bytes + [UInt8](repeating: 0, count: 16 - bytes.count))
    }
}
