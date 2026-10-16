import Foundation

public enum SimulatorPaths {
    public static let devicePlistName = "device.plist"
    public static let dataFolderName = "data"
    public static let appDataApplicationsPath = "Containers/Data/Application"
    public static let appBundleApplicationsPath = "Containers/Bundle/Application"
    public static let appGroupsPath = "data/Containers/Shared/AppGroup"
    public static let userDefaultsPath = "Library/Preferences"

    public static func coreSimulatorDevicesDirectoryURL(fileManager: FileManager = .default) -> URL? {
        fileManager
            .urls(for: .libraryDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Developer", isDirectory: true)
            .appendingPathComponent("CoreSimulator", isDirectory: true)
            .appendingPathComponent("Devices", isDirectory: true)
    }

    public static func formattedOSVersion(from runtimeIdentifier: String) -> String {
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
