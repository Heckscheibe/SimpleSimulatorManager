import Foundation
@testable import SimulatorCore
import Testing

@Suite("App snapshot capture: stopping the app")
struct AppSnapshotCaptureTerminationTests {
    @Test("Asked to, a capture stops the app before copying and says it did")
    func terminatesBeforeCopying() async throws {
        let environment = try SnapshotTestEnvironment()

        defer {
            environment.remove()
        }

        let capture = try await Self.capture(environment, terminatingApp: true)

        #expect(capture.termination == .terminated)
        #expect(environment.appActions.terminateCallCount == 1)
        #expect(environment.appActions.lastTerminatedApp?.bundleIdentifier == SnapshotTestEnvironment.bundleIdentifier)
        #expect(environment.appActions.lastTerminatedApp?.deviceUdid == "UDID-1")
    }

    @Test("An app that was not running is reported as such")
    func reportsNotRunning() async throws {
        let environment = try SnapshotTestEnvironment()

        defer {
            environment.remove()
        }

        environment.appActions.setOutcome(.notRunning)

        #expect(try await Self.capture(environment, terminatingApp: true).termination == .notRunning)
    }

    @Test("A failed terminate is reported, and the capture still goes ahead")
    func survivesTerminateFailure() async throws {
        let environment = try SnapshotTestEnvironment()

        defer {
            environment.remove()
        }

        environment.appActions.setError(NSError(domain: "ShellCommand", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom"]))

        let capture = try await Self.capture(environment, terminatingApp: true)

        #expect(capture.termination == .failed(message: "boom"))
        #expect(!capture.snapshot.manifest.containers.isEmpty)
    }

    @Test("Without the option the app is left alone")
    func leavesAppRunning() async throws {
        let environment = try SnapshotTestEnvironment()

        defer {
            environment.remove()
        }

        #expect(try await Self.capture(environment, terminatingApp: false).termination == .notRequested)
        #expect(environment.appActions.terminateCallCount == 0)
    }

    @Test("A capture that would find nothing fails before the app is stopped")
    func checksBeforeTerminating() async throws {
        let environment = try SnapshotTestEnvironment()

        defer {
            environment.remove()
        }

        await #expect(throws: AppSnapshotError.nothingInContents(.databases)) {
            try await environment.service.captureSnapshot(of: environment.target,
                                                          label: "Baseline",
                                                          contents: .databases,
                                                          includeCaches: false,
                                                          terminatingApp: true,
                                                          progress: nil)
        }
        #expect(environment.appActions.terminateCallCount == 0)
    }

    @Test("A restore says whether the app was stopped first")
    func restoreReportsTermination() async throws {
        let environment = try SnapshotTestEnvironment()

        defer {
            environment.remove()
        }

        let snapshot = try await Self.capture(environment, terminatingApp: false).snapshot
        environment.appActions.setError(NSError(domain: "ShellCommand", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom"]))

        let plan = try await environment.service.prepareRestore(of: snapshot, to: environment.target)
        let restore = try await environment.service.restore(plan, progress: nil)

        #expect(restore.termination == .failed(message: "boom"))
        #expect(restore.safetySnapshot.manifest.isSafetySnapshot)
    }

    @Test("A snapshot can be found by its id alone")
    func findsByID() async throws {
        let environment = try SnapshotTestEnvironment()

        defer {
            environment.remove()
        }

        let snapshot = try await Self.capture(environment, terminatingApp: false).snapshot

        #expect(await environment.service.snapshot(withID: snapshot.id)?.manifest == snapshot.manifest)
        #expect(await environment.service.snapshot(withID: "missing") == nil)
    }

    private static func capture(_ environment: SnapshotTestEnvironment, terminatingApp: Bool) async throws -> SnapshotCapture {
        try await environment.service.captureSnapshot(of: environment.target,
                                                      label: "Baseline",
                                                      contents: .everything,
                                                      includeCaches: false,
                                                      terminatingApp: terminatingApp,
                                                      progress: nil)
    }
}
