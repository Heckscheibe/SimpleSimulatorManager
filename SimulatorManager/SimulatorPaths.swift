import Foundation

enum SimulatorPaths {
    static let devicePlistName = "device.plist"
    static let dataFolderName = "data"
    static let appDataApplicationsPath = "Containers/Data/Application"
    static let appBundleApplicationsPath = "Containers/Bundle/Application"
    static let appGroupsPath = "data/Containers/Shared/AppGroup"
    static let userDefaultsPath = "Library/Preferences"

    static func coreSimulatorDevicesDirectoryURL(fileManager: FileManager = .default) -> URL? {
        fileManager
            .urls(for: .libraryDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Developer", isDirectory: true)
            .appendingPathComponent("CoreSimulator", isDirectory: true)
            .appendingPathComponent("Devices", isDirectory: true)
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
