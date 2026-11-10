import Foundation
@testable import SimulatorCore
import Testing

/// A scoped walk opens every candidate file to read its header, so how often a capture walks a
/// container is what it costs.
@Suite("Snapshot capture: walking the container")
struct SnapshotCaptureWalkTests {
    @Test("A scoped capture walks the container once, and once more before stopping the app",
          arguments: [false, true])
    func walkCount(terminatingApp: Bool) async throws {
        let environment = try Self.makeEnvironment()
        let counter = SnapshotWalkCounting.startCounting(environment.container.url)

        defer {
            SnapshotWalkCounting.stopCounting(environment.container.url)
            environment.remove()
        }

        // One walk of the same container on its own: what a single walk reads.
        _ = SnapshotContainerFiles.entriesByRelativePath(in: environment.container.url,
                                                         scope: SnapshotScope(contents: .databases, includeCaches: false))
        let headerReadsPerWalk = counter.headerReads
        try #require(counter.walks == 1)
        try #require(headerReadsPerWalk > 0)

        let capture = try await environment.service.captureSnapshot(of: environment.target,
                                                                    label: "Baseline",
                                                                    contents: .databases,
                                                                    includeCaches: false,
                                                                    terminatingApp: terminatingApp,
                                                                    progress: nil)

        // The pre-termination existence check, then the one listing that sizes and copies.
        let expectedWalks = terminatingApp ? 2 : 1
        let captureWalks = counter.walks - 1
        let captureHeaderReads = counter.headerReads - headerReadsPerWalk
        #expect(captureWalks == expectedWalks)
        #expect(captureHeaderReads == expectedWalks * headerReadsPerWalk)
        #expect(Self.payloadFiles(of: capture.snapshot) == [Self.storePath, "\(Self.storePath)-wal"])
    }

    @Test("A file that vanishes between listing and copying is skipped, and the capture still succeeds")
    func vanishedFileIsSkipped() async throws {
        let environment = try SnapshotTestEnvironment(includeAppGroup: false)

        defer {
            environment.remove()
        }

        try environment.container.write("first", at: "Documents/a.txt")
        let doomedURL = try environment.container.write("doomed", at: "Documents/z.txt")
        let totals = ProgressTotals()

        let snapshot = try await environment.service.captureSnapshot(
            of: environment.target,
            label: "Baseline",
            contents: .everything,
            includeCaches: false,
            progress: { progress in
                totals.record(progress.totalByteCount)

                // Files in a directory are copied in name order, so z.txt is still to come.
                if progress.currentRelativePath == "Documents/a.txt" {
                    try? FileManager.default.removeItem(at: doomedURL)
                }
            }
        )

        let files = Self.payloadFiles(of: snapshot)
        #expect(files.contains("Documents/a.txt"))
        #expect(!files.contains("Documents/z.txt"))
        // The total was known from the start, and included the file that later vanished.
        #expect(totals.values.count == 1)
        #expect(totals.values.first == snapshot.manifest.totalByteSize + Int64("doomed".utf8.count))
    }
}

private extension SnapshotCaptureWalkTests {
    static let storePath = "Library/Application Support/Model.sqlite"

    /// The standard fixture plus a SQLite store with its `-wal`, and enough other files for each
    /// walk to read a measurable number of headers.
    static func makeEnvironment() throws -> SnapshotTestEnvironment {
        let environment = try SnapshotTestEnvironment(includeAppGroup: false)
        try environment.container.writeSQLiteDatabase(at: storePath)
        try environment.container.write("wal", at: "\(storePath)-wal")

        for index in 0 ..< 20 {
            try environment.container.write("document \(index)", at: "Documents/file-\(index).txt")
        }

        return environment
    }

    static func payloadFiles(of snapshot: AppSnapshot) -> Set<String> {
        let containers = snapshot.manifest.containers

        return Set(containers.flatMap { container in
            SnapshotContainerFiles
                .fileSizesByRelativePath(in: snapshot.payloadURL(for: container), scope: .everything(includeCaches: true))
                .keys
        })
    }
}

/// Every distinct total a capture reported, collected from its progress callback.
private final class ProgressTotals: @unchecked Sendable {
    private let lock = NSLock()
    private var totals: Set<Int64> = []

    var values: Set<Int64> {
        lock.withLock { totals }
    }

    func record(_ total: Int64) {
        lock.withLock { _ = totals.insert(total) }
    }
}
