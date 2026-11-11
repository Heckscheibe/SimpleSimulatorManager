import Foundation
import Testing
@testable import SimulatorCore

@Suite("FolderEventPathFilter")
struct FolderEventPathFilterTests {
    private let root = URL(fileURLWithPath: "/Devices/ABC/data", isDirectory: true)
    private let packages = URL(fileURLWithPath: "/Devices/ABC/data/Containers/Bundle/Application", isDirectory: true)

    private func makeFilter() throws -> FolderEventPathFilter {
        try #require(FolderEventPathFilter(watchedRoot: root, relevantFolder: packages))
    }

    @Test("The relevant folder and anything inside it pass", arguments: [
        "/Devices/ABC/data/Containers/Bundle/Application",
        "/Devices/ABC/data/Containers/Bundle/Application/",
        "/Devices/ABC/data/Containers/Bundle/Application/1234-UUID/",
        "/Devices/ABC/data/Containers/Bundle/Application/1234-UUID/Probe.app/"
    ])
    func relevantFolderAndDescendantsPass(eventPath: String) throws {
        #expect(try makeFilter().isRelevant(eventPath: eventPath))
    }

    /// Creating `Bundle` is reported on `Containers/`, and FSEvents reports a dropped-event rescan
    /// on the watched root itself, so ancestors have to pass or the first install goes unnoticed.
    @Test("Ancestors of the relevant folder under the root pass", arguments: [
        "/Devices/ABC/data",
        "/Devices/ABC/data/",
        "/Devices/ABC/data/Containers/",
        "/Devices/ABC/data/Containers/Bundle/"
    ])
    func ancestorsPass(eventPath: String) throws {
        #expect(try makeFilter().isRelevant(eventPath: eventPath))
    }

    /// The paths a booting simulator actually rewrites, taken from an FSEvents recording.
    @Test("Busy unrelated folders under the root are dropped", arguments: [
        "/Devices/ABC/data/Library/Caches/com.apple.nsurlsessiond/",
        "/Devices/ABC/data/tmp/PFTemporaryDirectory/",
        "/Devices/ABC/data/var/db/uuidtext/AB/",
        "/Devices/ABC/data/Containers/Data/Application/5678-UUID/Library/",
        "/Devices/ABC/data/Containers/Data/PluginKitPlugin/",
        "/Devices/ABC/data/Containers/Staging/",
        "/Devices/ABC/data/Containers/Shared/AppGroup/"
    ])
    func unrelatedPathsAreDropped(eventPath: String) throws {
        #expect(try !makeFilter().isRelevant(eventPath: eventPath))
    }

    @Test("A sibling sharing a name prefix is not mistaken for the folder or an ancestor", arguments: [
        "/Devices/ABC/data/Containers/Bundle/ApplicationX/",
        "/Devices/ABC/data/Containers/BundleCache/",
        "/Devices/ABC/data/ContainersOld/"
    ])
    func namePrefixSiblingsAreDropped(eventPath: String) throws {
        #expect(try !makeFilter().isRelevant(eventPath: eventPath))
    }

    @Test("A path that cannot be related to the root is forwarded rather than dropped")
    func unrelatablePathsAreForwarded() throws {
        let filter = try makeFilter()

        #expect(filter.isRelevant(eventPath: "/Somewhere/else/entirely/"))
        #expect(filter.isRelevant(eventPath: "/Devices/ABC/"))
        #expect(filter.isRelevant(eventPath: ""))
    }

    @Test("A root reached through a symlink also matches the resolved paths FSEvents reports")
    func resolvedRootSpellingMatches() throws {
        // `/var` is a symlink to `/private/var`, and FSEvents reports the latter.
        let temporaryRoot = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("FolderEventPathFilterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let resolvedRoot = try #require(realpath(temporaryRoot.path, nil).map { pointer in
            defer { free(pointer) }
            return String(cString: pointer)
        })
        try #require(resolvedRoot != temporaryRoot.standardizedFileURL.path, "the temporary directory should sit behind a symlink")

        let filter = try #require(FolderEventPathFilter(
            watchedRoot: temporaryRoot,
            relevantFolder: temporaryRoot.appendingPathComponent("Containers/Bundle/Application", isDirectory: true)
        ))

        #expect(filter.isRelevant(eventPath: resolvedRoot + "/Containers/Bundle/Application/1234/"))
        #expect(filter.isRelevant(eventPath: resolvedRoot + "/Containers/"))
        #expect(!filter.isRelevant(eventPath: resolvedRoot + "/Library/Caches/"))
        #expect(!filter.isRelevant(eventPath: temporaryRoot.path + "/Library/Caches/"))
    }

    /// How the app actually builds it: both URLs from the same resolved device folder, the root
    /// existing and the packages folder not yet. `standardizedFileURL` would strip `/private` from
    /// the existing root only, and the two would no longer line up.
    @Test("An existing resolved root and its missing folder still line up")
    func existingResolvedRootWithMissingFolder() throws {
        let temporaryRoot = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("FolderEventPathFilterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let resolvedRoot = try #require(realpath(temporaryRoot.path, nil).map { pointer in
            defer { free(pointer) }
            return String(cString: pointer)
        })
        let root = URL(fileURLWithPath: resolvedRoot, isDirectory: true)

        let filter = try #require(FolderEventPathFilter(
            watchedRoot: root,
            relevantFolder: root.appendingPathComponent("Containers/Bundle/Application")
        ))

        #expect(filter.isRelevant(eventPath: resolvedRoot + "/Containers/Bundle/"))
        #expect(!filter.isRelevant(eventPath: resolvedRoot + "/Library/Caches/"))
    }

    @Test("A relevant folder outside the watched root makes no filter", arguments: [
        "/Devices/ABC/data",
        "/Devices/ABC/other",
        "/Devices/ABC/dataX/Containers"
    ])
    func folderOutsideRootMakesNoFilter(relevantPath: String) {
        #expect(FolderEventPathFilter(watchedRoot: root, relevantFolder: URL(fileURLWithPath: relevantPath)) == nil)
    }
}
