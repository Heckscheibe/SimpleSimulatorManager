import Foundation
import Testing
@testable import SimulatorCore

@Suite("SimulatorRuntimeCleanupService Tests")
struct SimulatorRuntimeCleanupServiceTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let iOS26 = "com.apple.CoreSimulator.SimRuntime.iOS-26-4"

    private func image(
        _ identifier: String,
        runtime: String? = nil,
        version: String = "26.4",
        build: String = "23E1",
        state: String = "Ready",
        deletable: Bool = true,
        lastUsedDaysAgo: Int? = 1,
        sizeBytes: Int64? = 8_000_000_000
    ) -> SimctlRuntimeImageRecord {
        SimctlRuntimeImageRecord(
            identifier: identifier,
            runtimeIdentifier: runtime ?? iOS26,
            platformName: "iOS",
            version: version,
            build: build,
            state: state,
            isDeletable: deletable,
            sizeBytes: sizeBytes,
            lastUsedAt: lastUsedDaysAgo.map { now.addingTimeInterval(-TimeInterval($0) * 86400) }
        )
    }

    private func candidates(
        _ images: [SimctlRuntimeImageRecord],
        simulators: [RuntimeSimulatorRecord] = []
    ) -> [SimulatorRuntimeCleanupCandidate] {
        SimulatorRuntimeCleanupService.buildCandidates(
            images: images,
            simulators: simulators,
            now: now,
            unusedThresholdDays: 90
        )
    }

    @Test("a healthy, recently used runtime is not offered")
    func healthyRuntimeIsKept() {
        #expect(candidates([image("A")]).isEmpty)
    }

    @Test("an unusable runtime qualifies")
    func unusableQualifies() {
        let result = candidates([image("A", state: "Unusable")])

        #expect(result.map(\.reasons) == [[.unusable]])
    }

    @Test("transient states never qualify", arguments: ["Downloading", "Staging", "Verifying", "Mounting"])
    func transientStatesAreKept(state: String) {
        #expect(candidates([image("A", state: state)]).isEmpty)
    }

    @Test("an older build of the same runtime is superseded, and the newer one is kept")
    func olderBuildIsSuperseded() {
        let result = candidates([
            image("OLD", version: "26.4", build: "23E100"),
            image("NEW", version: "26.4.1", build: "23E254a")
        ])

        #expect(result.map(\.imageIdentifier) == ["OLD"])
        #expect(result.first?.reasons == [.superseded])
        #expect(result.first?.detailMessage?.contains("26.4.1 (23E254a)") == true)
    }

    @Test("same version falls back to the build number")
    func sameVersionComparesBuild() {
        let result = candidates([
            image("OLD", version: "26.4", build: "23E9"),
            image("NEW", version: "26.4", build: "23E10")
        ])

        #expect(result.map(\.imageIdentifier) == ["OLD"])
    }

    @Test("a beta build never supersedes the release build of the same version, nor the reverse")
    func betaAndReleaseBuildsAreNotOrdered() {
        let result = candidates([
            image("RELEASE", version: "26.0", build: "23A344"),
            image("BETA", version: "26.0", build: "23A5330a")
        ])

        #expect(result.isEmpty)
    }

    @Test("a patched re-release of a build supersedes the original")
    func patchedBuildSupersedes() {
        let result = candidates([
            image("ORIGINAL", version: "26.4", build: "23E254"),
            image("PATCHED", version: "26.4", build: "23E254a")
        ])

        #expect(result.map(\.imageIdentifier) == ["ORIGINAL"])
    }

    @Test("builds that cannot be parsed are never ordered")
    func unparseableBuildsAreKept() {
        let result = candidates([
            image("A", version: "26.4", build: "weird"),
            image("B", version: "26.4", build: "weirder")
        ])

        #expect(result.isEmpty)
    }

    @Test("build numbers order by major, letter, then minor")
    func buildOrdering() throws {
        let older = try #require(SimulatorRuntimeBuild("23E100"))

        #expect(try #require(SimulatorRuntimeBuild("24A1")).isNewer(than: older))
        #expect(try #require(SimulatorRuntimeBuild("23F1")).isNewer(than: older))
        #expect(try #require(SimulatorRuntimeBuild("23E101")).isNewer(than: older))
        #expect(!older.isNewer(than: SimulatorRuntimeBuild("23E101")))
        #expect(!older.isNewer(than: older))
        #expect(SimulatorRuntimeBuild("not-a-build") == nil)
    }

    @Test("an image that is still installing is never offered, even when older or long unused")
    func installingImageIsKept() {
        let result = candidates([
            image("OLD", version: "26.4", build: "1", state: "Verifying", lastUsedDaysAgo: 400),
            image("NEW", version: "26.5", build: "2")
        ])

        #expect(result.isEmpty)
    }

    @Test("the detail text says so when the newer build is listed for removal too")
    func replacementAlsoListed() {
        let result = candidates([
            image("OLD", version: "26.4", build: "1", lastUsedDaysAgo: 200),
            image("NEW", version: "26.5", build: "2", lastUsedDaysAgo: 200)
        ])

        let old = result.first { $0.imageIdentifier == "OLD" }
        #expect(old?.detailMessage?.contains("listed for removal too") == true)
    }

    @Test("versions compare numerically, not as strings")
    func versionsCompareNumerically() {
        let result = candidates([
            image("NINE", version: "26.9", build: "A"),
            image("TEN", version: "26.10", build: "B")
        ])

        #expect(result.map(\.imageIdentifier) == ["NINE"])
    }

    @Test("a newer image that is not ready does not supersede a working one")
    func brokenNewerImageDoesNotSupersede() {
        let result = candidates([
            image("OLD", version: "26.4", build: "1"),
            image("NEW", version: "26.5", build: "2", state: "Downloading")
        ])

        #expect(result.isEmpty)
    }

    @Test("runtimes of different identifiers never supersede each other")
    func differentRuntimesAreIndependent() {
        let result = candidates([
            image("A", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-26-4", version: "26.4"),
            image("B", runtime: "com.apple.CoreSimulator.SimRuntime.iOS-27-0", version: "27.0")
        ])

        #expect(result.isEmpty)
    }

    @Test("unused qualifies only past the threshold")
    func unusedThreshold() {
        #expect(candidates([image("A", lastUsedDaysAgo: 89)]).isEmpty)
        #expect(candidates([image("A", lastUsedDaysAgo: 91)]).map(\.reasons) == [[.unused]])
    }

    @Test("a missing last-used date is not evidence of staleness")
    func missingLastUsedIsKept() {
        #expect(candidates([image("A", lastUsedDaysAgo: nil)]).isEmpty)
    }

    @Test("images simctl calls not deletable are never offered")
    func nonDeletableIsKept() {
        #expect(candidates([image("A", state: "Unusable", deletable: false, lastUsedDaysAgo: 400)]).isEmpty)
    }

    @Test("reasons combine and sort the most serious first")
    func reasonsCombine() {
        let result = candidates([
            image("OLD", version: "26.4", build: "1", state: "Unusable", lastUsedDaysAgo: 200),
            image("NEW", version: "26.5", build: "2")
        ])

        #expect(result.first?.reasons == [.unusable, .superseded, .unused])
    }

    @Test("an unused runtime strands the simulators on it, and counts the running ones")
    func unusedRuntimeAffectsSimulators() {
        let result = candidates(
            [image("A", lastUsedDaysAgo: 120)],
            simulators: [
                RuntimeSimulatorRecord(runtimeIdentifier: iOS26, isBooted: true),
                RuntimeSimulatorRecord(runtimeIdentifier: iOS26, isBooted: false),
                RuntimeSimulatorRecord(runtimeIdentifier: "other", isBooted: true)
            ]
        )

        #expect(result.first?.affectedSimulatorCount == 2)
        #expect(result.first?.bootedSimulatorCount == 1)
    }

    @Test("a superseded runtime strands nothing while its replacement stays")
    func supersededRuntimeAffectsNoSimulators() {
        let result = candidates(
            [image("OLD", version: "26.4", build: "1"), image("NEW", version: "26.4.1", build: "2")],
            simulators: [RuntimeSimulatorRecord(runtimeIdentifier: iOS26, isBooted: false)]
        )

        #expect(result.first?.affectedSimulatorCount == 0)
    }

    @Test("when the replacement is a candidate too, the simulators count as affected")
    func replacementThatIsAlsoCandidate() {
        let result = candidates(
            [
                image("OLD", version: "26.4", build: "1", lastUsedDaysAgo: 200),
                image("NEW", version: "26.5", build: "2", lastUsedDaysAgo: 200)
            ],
            simulators: [RuntimeSimulatorRecord(runtimeIdentifier: iOS26, isBooted: false)]
        )

        #expect(result.allSatisfy { $0.affectedSimulatorCount == 1 })
    }

    @Test("candidates sort by seriousness, then size")
    func sorting() {
        let result = candidates([
            image("UNUSED-BIG", runtime: "r1", lastUsedDaysAgo: 200, sizeBytes: 9),
            image("UNUSED-SMALL", runtime: "r2", lastUsedDaysAgo: 200, sizeBytes: 1),
            image("BROKEN", runtime: "r3", state: "Unusable", sizeBytes: 0)
        ])

        #expect(result.map(\.imageIdentifier) == ["BROKEN", "UNUSED-BIG", "UNUSED-SMALL"])
    }

    @Test("parses the shape simctl prints")
    func parsesSimctlJSON() throws {
        let json = """
        {
          "4F6FF840-413D-4120-99FA-D6ED54DB6A55" : {
            "build" : "23E254a",
            "deletable" : true,
            "identifier" : "4F6FF840-413D-4120-99FA-D6ED54DB6A55",
            "lastUsedAt" : "2026-10-26T13:27:41Z",
            "platformIdentifier" : "com.apple.platform.iphonesimulator",
            "runtimeIdentifier" : "com.apple.CoreSimulator.SimRuntime.iOS-26-4",
            "sizeBytes" : 8485014416,
            "state" : "Ready",
            "version" : "26.4.1"
          },
          "425F7809-BBBE-49EB-ABFC-E9107FD7379D" : {
            "build" : "24R362",
            "deletable" : true,
            "runtimeIdentifier" : "com.apple.CoreSimulator.SimRuntime.xrOS-27-0",
            "state" : "Ready",
            "version" : "27.0"
          }
        }
        """

        let images = try SimulatorRuntimeCleanupService.parseRuntimeImages(from: Data(json.utf8))

        #expect(images.count == 2)
        let ios = try #require(images.first { $0.version == "26.4.1" })
        #expect(ios.platformName == "iOS")
        #expect(ios.sizeBytes == 8_485_014_416)
        #expect(ios.lastUsedAt != nil)
        #expect(ios.isReady)
        let vision = try #require(images.first { $0.version == "27.0" })
        #expect(vision.platformName == "visionOS")
        #expect(vision.lastUsedAt == nil)
    }

    @Test("an image without the deletable flag is treated as not deletable")
    func missingDeletableFlag() throws {
        let json = #"{"A":{"runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.iOS-26-4","state":"Unusable"}}"#
        let images = try SimulatorRuntimeCleanupService.parseRuntimeImages(from: Data(json.utf8))

        #expect(candidates(images).isEmpty)
    }

    @Test("rejects malformed output instead of reporting nothing to clean")
    func malformedOutputThrows() {
        #expect(throws: (any Error).self) {
            try SimulatorRuntimeCleanupService.parseRuntimeImages(from: Data("not json".utf8))
        }
    }

    @Test("parses simulators per runtime and notes which are booted")
    func parsesSimulators() throws {
        let json = #"{"devices":{"rt1":[{"state":"Booted"},{"state":"Shutdown"}],"rt2":[]}}"#
        let simulators = try SimulatorRuntimeCleanupService.parseSimulators(from: Data(json.utf8))

        #expect(simulators.count == 2)
        #expect(simulators.count(where: \.isBooted) == 1)
    }

    @Test("deleting refuses an identifier that is not an image UUID")
    func refusesNonUUIDIdentifier() async {
        let candidate = SimulatorRuntimeCleanupCandidate(
            imageIdentifier: "--all",
            runtimeIdentifier: iOS26,
            platformName: "iOS",
            version: "26.4",
            build: "1",
            sizeBytes: nil,
            lastUsedAt: nil,
            reasons: [.unused],
            affectedSimulatorCount: 0,
            bootedSimulatorCount: 0,
            detailMessage: nil
        )

        await #expect(throws: (any Error).self) {
            try await SimulatorRuntimeCleanupService().deleteRuntimeCandidate(candidate)
        }
    }
}
