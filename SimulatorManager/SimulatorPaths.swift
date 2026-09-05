import Foundation

enum SimulatorPaths {
    static let devicePlistName = "device.plist"
    static let dataFolderName = "data"
    static let appDataApplicationsPath = "Containers/Data/Application"
    static let appBundleApplicationsPath = "Containers/Bundle/Application"
    static let appGroupsPath = "data/Containers/Shared/AppGroup"
    static let userDefaultsPath = "Library/Preferences"

    /// Container subtrees that hold regenerable data. Snapshots leave them out by default: both
    /// are rebuilt by the app on demand and are frequently the bulk of a container's size.
    static let cachesPath = "Library/Caches"
    static let temporaryPath = "tmp"

    static let applicationSupportFolderName = "SimulatorManager"
    static let snapshotsFolderName = "Snapshots"

    static func coreSimulatorDevicesDirectoryURL(fileManager: FileManager = .default) -> URL? {
        fileManager
            .urls(for: .libraryDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Developer", isDirectory: true)
            .appendingPathComponent("CoreSimulator", isDirectory: true)
            .appendingPathComponent("Devices", isDirectory: true)
    }

    /// Where app container snapshots are kept.
    ///
    /// Deliberately outside the simulator: a snapshot has to outlive the app being uninstalled and
    /// the device being erased, which is much of the point of taking one.
    static func snapshotsRootURL(fileManager: FileManager = .default) -> URL? {
        fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(applicationSupportFolderName, isDirectory: true)
            .appendingPathComponent(snapshotsFolderName, isDirectory: true)
    }

    static func formattedOSVersion(from runtimeIdentifier: String) -> String {
        guard let lastComponent = runtimeIdentifier.split(separator: ".").last else {
            return runtimeIdentifier
        }

        let parts = lastComponent.split(separator: "-")
        guard let platform = parts.first else {
            return String(lastComponent)
        }

        let version = parts.dropFirst().joined(separator: ".")
        guard !version.isEmpty else {
            return String(platform)
        }

        return "\(platform) \(version)"
    }
}
