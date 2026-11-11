import Combine
import Foundation
import Testing
@testable import SimulatorCore
import SimulatorCoreTestSupport

/// The watch on a device with no app installed yet, such as one just erased: it has to sit on the
/// busy `data` folder and still notice the first install promptly.
@Suite("AppFolderMonitor fallback watch", .serialized)
struct AppFolderMonitorFallbackTests {
    private let udid = "55555555-5555-5555-5555-555555555555"

    // MARK: - Watch target

    @Test("An existing packages folder is watched directly, without a filter")
    func existingPackagesFolderIsWatchedDirectly() throws {
        let fixture = try DeviceFixtureDirectory()
        defer { fixture.remove() }

        let device = try makeDevice(in: fixture)
        let packagesFolder = try #require(device.appPackagesFolder)
        try FileManager.default.createDirectory(at: packagesFolder, withIntermediateDirectories: true)

        let target = try #require(AppFolderMonitor.watchTarget(for: device))

        #expect(target.url.path == packagesFolder.path)
        #expect(target.relevantFolder == nil)
        #expect(!target.isFallback)
    }

    @Test("Without a packages folder, the data folder is watched, filtered to the packages folder")
    func missingPackagesFolderFallsBackToFilteredDataFolder() throws {
        let fixture = try DeviceFixtureDirectory()
        defer { fixture.remove() }

        let device = try makeDevice(in: fixture)
        // What a booted, freshly erased simulator has: `Containers` without `Bundle`.
        for path in ["Containers/Data/Application", "Containers/Shared/AppGroup", "Containers/Staging"] {
            try FileManager.default.createDirectory(at: #require(device.dataFolder).appendingPathComponent(path),
                                                    withIntermediateDirectories: true)
        }

        let target = try #require(AppFolderMonitor.watchTarget(for: device))

        #expect(target.url.path == device.dataFolder?.path)
        #expect(target.relevantFolder?.path == device.appPackagesFolder?.path)
        #expect(target.isFallback)
    }

    @Test("A packages path that exists as a file is not mistaken for the folder")
    func packagesPathAsFileFallsBack() throws {
        let fixture = try DeviceFixtureDirectory()
        defer { fixture.remove() }

        let device = try makeDevice(in: fixture)
        let packagesFolder = try #require(device.appPackagesFolder)
        try FileManager.default.createDirectory(at: packagesFolder.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: packagesFolder)

        #expect(AppFolderMonitor.watchTarget(for: device)?.isFallback == true)
    }

    @Test("A device without a folder has nothing to watch")
    func deviceWithoutURLHasNoTarget() throws {
        let fixture = try DeviceFixtureDirectory()
        defer { fixture.remove() }

        let device = try makeDevice(in: fixture)
        device.url = nil

        #expect(AppFolderMonitor.watchTarget(for: device) == nil)
        #expect(AppFolderMonitor(device: device).isMonitoring == false)
    }

    // MARK: - Behaviour against real FSEvents

    @Test("The filtered fallback ignores changes elsewhere under data and reports the packages folder appearing")
    func filteredFolderMonitorIgnoresNoise() async throws {
        // The unresolved temporary directory (`/var/…`), so the resolved spelling FSEvents reports
        // (`/private/var/…`) has to be matched too.
        let dataFolder = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("AppFolderMonitorFallbackTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("data", isDirectory: true)
        try FileManager.default.createDirectory(at: dataFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dataFolder.deletingLastPathComponent()) }
        try createNoiseFolders(in: dataFolder)
        try await settle()

        let packagesFolder = dataFolder.appendingPathComponent(SimulatorPaths.appBundleApplicationsPath, isDirectory: true)
        let filter = try #require(FolderEventPathFilter(watchedRoot: dataFolder, relevantFolder: packagesFolder))
        let monitor = FolderMonitor(url: dataFolder, latency: 0.1, eventFilter: filter)
        try monitor.startMonitoring()
        defer { try? monitor.stopMonitoring() }

        let counter = EmissionCounter()
        let subscription = monitor.folderDidChange.sink { counter.record() }
        defer { subscription.cancel() }

        for index in 0 ..< 10 {
            try writeNoise(in: dataFolder, index: index)
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        try await Task.sleep(nanoseconds: 1_000_000_000)
        #expect(!counter.hasEmitted, "changes outside the packages folder should not be reported")

        try FileManager.default.createDirectory(at: packagesFolder.appendingPathComponent("1234-UUID"),
                                                withIntermediateDirectories: true)

        #expect(await counter.waitForEmission(timeout: 5))
    }

    /// The regression this watch exists for: while the simulator keeps writing elsewhere under
    /// `data` faster than the debounce window, the first install must still be reported. Watching
    /// `data` unfiltered, every noise write restarts the debounce and nothing is reported until the
    /// noise stops.
    @Test("The first install is reported while the device keeps writing elsewhere under data")
    func firstInstallIsReportedDespiteContinuousNoise() async throws {
        let fixture = try DeviceFixtureDirectory()
        defer { fixture.remove() }

        let device = try makeDevice(in: fixture)
        let dataFolder = try #require(device.dataFolder)
        let packagesFolder = try #require(device.appPackagesFolder)
        try createNoiseFolders(in: dataFolder)
        try await settle()

        let monitor = AppFolderMonitor(device: device)
        // Released after its last use otherwise, which would stop the watch mid-test.
        defer { withExtendedLifetime(monitor) {} }
        #expect(monitor.isWatchingFallback)
        #expect(monitor.isMonitoring)

        let counter = EmissionCounter()
        let subscription = monitor.appfolderDidChange.sink { _ in counter.record() }
        defer { subscription.cancel() }

        // Noise every 0.3 s for 10 s, well inside the 3 s debounce window.
        let noise = Task.detached {
            for index in 0 ..< 34 {
                try? writeNoise(in: dataFolder, index: index)
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
        defer { noise.cancel() }

        try await Task.sleep(nanoseconds: 1_000_000_000)
        try FileManager.default.createDirectory(at: packagesFolder.appendingPathComponent("1234-UUID/Probe.app"),
                                                withIntermediateDirectories: true)

        // 3 s debounce plus slack, and still well before the noise stops.
        #expect(await counter.waitForEmission(timeout: 6))
    }

    // MARK: - Helpers

    private func makeDevice(in fixture: DeviceFixtureDirectory) throws -> Device {
        try fixture.writeDevice(udid: udid, name: "iPhone 16 Pro")
        let device = try #require(DeviceLoader(devicesDirectoryURL: fixture.url).loadDeviceList().first)
        try FileManager.default.createDirectory(at: #require(device.dataFolder).appendingPathComponent("Library"),
                                                withIntermediateDirectories: true)
        return device
    }
}

/// FSEvents can deliver changes made just before a stream started, so setup has to settle first,
/// or the folders it created are reported on `data` (an ancestor, which the filter lets through).
private func settle() async throws {
    try await Task.sleep(nanoseconds: 500_000_000)
}

private let noiseFolders = ["Library/Caches/com.apple.nsurlsessiond", "tmp/PFTemporaryDirectory", "Containers/Data/Application/SYSTEM"]

/// The folders a booted simulator keeps writing to. Created up front, as on a real device: creating
/// a folder directly in `data` or `Containers` is reported on an ancestor of the packages folder,
/// which the filter deliberately lets through.
private func createNoiseFolders(in dataFolder: URL) throws {
    for folder in noiseFolders {
        try FileManager.default.createDirectory(at: dataFolder.appendingPathComponent(folder, isDirectory: true),
                                                withIntermediateDirectories: true)
    }
}

/// Writes where a booting simulator does: caches, temporary files and system data containers.
private func writeNoise(in dataFolder: URL, index: Int) throws {
    let folder = dataFolder.appendingPathComponent(noiseFolders[index % noiseFolders.count], isDirectory: true)
    try Data("\(index)".utf8).write(to: folder.appendingPathComponent("noise-\(index)"))
}

/// Counts emissions from any thread and lets a test wait for the first one.
private final class EmissionCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var emissions = 0

    var hasEmitted: Bool {
        lock.withLock { emissions > 0 }
    }

    func record() {
        lock.withLock { emissions += 1 }
    }

    func waitForEmission(timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if hasEmitted {
                return true
            }

            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        return hasEmitted
    }
}
