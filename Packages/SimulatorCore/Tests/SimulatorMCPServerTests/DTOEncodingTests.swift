import Foundation
@testable import SimulatorCore
@testable import SimulatorMCPServer
import Testing

@Suite("DTO encoding")
struct DTOEncodingTests {
    private func json(_ value: some Encodable) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: JSONOutput.data(value))
        return try #require(object as? [String: Any])
    }

    @Test("Dates are ISO 8601 strings")
    func datesAreISO8601() throws {
        let device = Device(udid: "A", name: "iPhone", state: .running, simulatorPlatform: .iPhone, osVersion: "iOS 26.1")
        let app = SimulatoriOSApp(displayName: "Notes",
                                  bundleIdentifier: Sample.appBundleId,
                                  appDocumentsFolderURL: nil,
                                  appPackageURL: nil,
                                  hasWatchApp: false,
                                  userDefaultsDomains: [])
        let change = AppChange(app: app, device: device, changeType: .installed, timestamp: Date(timeIntervalSince1970: 0))

        let encoded = try json(RecentAppDTO(appChange: change))

        #expect(encoded["changedAt"] as? String == "1970-01-01T00:00:00Z")
    }

    @Test("Absent optional fields are left out rather than written as null")
    func optionalFieldsAreOmitted() throws {
        let device = Device(udid: "A", name: "iPhone", state: .off, simulatorPlatform: .iPad, osVersion: "iOS 26.1")

        let encoded = try json(DeviceDTO(device: device))

        #expect(encoded["lastBootedAt"] == nil)
        #expect(encoded["deviceFolder"] == nil)
        #expect(encoded["platform"] as? String == "iPad")
        #expect(encoded["state"] as? String == "off")
        #expect(encoded.keys.contains("udid"))
    }

    @Test("Paths are absolute strings without escaped slashes")
    func pathsAreAbsoluteStrings() throws {
        let dataContainer = URL(fileURLWithPath: "/Users/me/Library/Developer/CoreSimulator/Devices/A/data/Containers/Data/Application/B")
        let appBundle = URL(fileURLWithPath: "/Users/me/Library/Developer/CoreSimulator/Devices/A/data/Containers/Bundle/Application/C/Notes.app")
        let app = SimulatoriOSApp(displayName: "Notes",
                                  bundleIdentifier: Sample.appBundleId,
                                  appDocumentsFolderURL: dataContainer,
                                  appPackageURL: appBundle,
                                  hasWatchApp: false,
                                  userDefaultsDomains: [Sample.appBundleId])

        let dto = AppContainersDTO(udid: "A", app: app, appGroups: [])
        let text = try String(decoding: JSONOutput.data(dto), as: UTF8.self)
        let encoded = try json(dto)

        #expect(encoded["dataContainer"] as? String == dataContainer.path)
        #expect(encoded["bundleContainer"] as? String == appBundle.deletingLastPathComponent().path)
        #expect(encoded["appBundle"] as? String == appBundle.path)
        #expect(encoded["preferencesFolder"] as? String == dataContainer.appendingPathComponent("Library/Preferences").path)
        #expect(!text.contains("\\/"))
    }

    @Test("The preferences folder is left out until the app wrote preferences, like the menu item")
    func preferencesFolderNeedsUserDefaults() throws {
        let app = SimulatoriOSApp(displayName: "Notes",
                                  bundleIdentifier: Sample.appBundleId,
                                  appDocumentsFolderURL: URL(fileURLWithPath: "/tmp/B"),
                                  appPackageURL: nil,
                                  hasWatchApp: false,
                                  userDefaultsDomains: [])

        let encoded = try json(AppContainersDTO(udid: "A", app: app, appGroups: []))

        #expect(encoded["preferencesFolder"] == nil)
        #expect(encoded["bundleContainer"] == nil)
    }

    @Test("Apps report kind, watch companion and the menu's exportable domains")
    func appFields() throws {
        let iOSApp = SimulatoriOSApp(displayName: "Notes",
                                     bundleIdentifier: Sample.appBundleId,
                                     appDocumentsFolderURL: nil,
                                     appPackageURL: nil,
                                     hasWatchApp: true,
                                     userDefaultsDomains: ["com.apple.UIKit", Sample.appBundleId, Sample.suiteDomain])
        let watchApp = SimulatorWatchOSApp(displayName: "Notes Watch",
                                           bundleIdentifier: "com.example.notes.watchkitapp",
                                           appDocumentsFolderURL: nil,
                                           appPackageURL: nil,
                                           userDefaultsDomains: [],
                                           companioniOSAppBundleIdentifier: Sample.appBundleId)

        let iOS = try json(AppDTO(app: iOSApp))
        let watch = try json(AppDTO(app: watchApp))

        #expect(iOS["kind"] as? String == "iOS")
        #expect(iOS["hasWatchApp"] as? Bool == true)
        #expect(iOS["userDefaultsDomains"] as? [String] == [Sample.appBundleId, Sample.suiteDomain])
        #expect(watch["kind"] as? String == "watchOS")
        #expect(watch["companionBundleIdentifier"] as? String == Sample.appBundleId)
        #expect(watch["hasWatchApp"] as? Bool == false)
    }

    @Test("Cleanup candidates carry reasons, disk usage and how they are deleted")
    func cleanupCandidateFields() throws {
        let simctl = try json(CleanupCandidateDTO(candidate: CleanupCandidateFactory.simctlCandidate()))
        let directory = try json(CleanupCandidateDTO(candidate: CleanupCandidateFactory.directoryCandidate()))

        #expect(simctl["reasons"] as? [String] == ["missingRuntime", "unavailable"])
        #expect(simctl["reasonSummary"] as? String == "Missing Runtime, Unavailable")
        #expect(simctl["diskUsageBytes"] as? Int == 2048)
        #expect(simctl["deletionMethod"] as? String == "simctlDelete")
        #expect(simctl["directory"] == nil)
        #expect(simctl["platform"] as? String == "iPhone")
        #expect(directory["deletionMethod"] as? String == "trashDirectory")
        #expect(directory["directory"] as? String == "/tmp/Devices/ABC")
        #expect(directory["udid"] == nil)
        #expect(directory["diskUsageBytes"] == nil)
    }

    @Test("Tool results carry the same JSON as text and as structured content")
    func resultsCarryStructuredContent() throws {
        let device = Device(udid: "A", name: "iPhone", state: .running, simulatorPlatform: .iPhone, osVersion: "iOS 26.1")

        let result = try JSONOutput.result(["device": DeviceDTO(device: device)])

        #expect(result.isError == false)
        #expect(result.structuredContent?.objectValue?["device"]?.objectValue?["udid"]?.stringValue == "A")
        #expect(try result.json()["device"] != nil)
    }
}
