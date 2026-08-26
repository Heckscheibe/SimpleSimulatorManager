//
//  ContainerContentServiceTests.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 25.08.26.
//

import Foundation
import Testing
@testable import SimulatorManager

@Suite("ContainerContentService Tests")
struct ContainerContentServiceTests {
    @MainActor
    private func makeService(
        pasteboard: MockPasteboard,
        exporter: MockUserDefaultsExporter? = nil,
        errorReporter: MockUserFacingErrorReporter? = nil
    ) -> ContainerContentService {
        ContainerContentService(pasteboard: pasteboard,
                                exporter: exporter ?? MockUserDefaultsExporter(),
                                errorReporter: errorReporter ?? MockUserFacingErrorReporter())
    }

    @Test("An ordinary container path is copied verbatim")
    @MainActor
    func ordinaryPathIsCopiedVerbatim() {
        let pasteboard = MockPasteboard()
        let path = "/Users/tester/Library/Developer/CoreSimulator/Devices/ABC-123/data"

        makeService(pasteboard: pasteboard).copyPath(of: URL(fileURLWithPath: path))

        #expect(pasteboard.lastWrittenString == path)
    }

    @Test("A path containing spaces is escaped so it still resolves when pasted into a terminal")
    @MainActor
    func pathWithSpacesIsEscaped() {
        let pasteboard = MockPasteboard()

        makeService(pasteboard: pasteboard).copyPath(of: URL(fileURLWithPath: "/tmp/My Simulator/App Data"))

        #expect(pasteboard.lastWrittenString == "/tmp/My\\ Simulator/App\\ Data")
    }

    @Test("Exported UserDefaults JSON lands on the clipboard")
    @MainActor
    func userDefaultsJSONIsCopied() {
        let pasteboard = MockPasteboard()
        let exporter = MockUserDefaultsExporter()
        exporter.result = .success("{ \"key\" : 1 }")
        let preferencesURL = URL(fileURLWithPath: "/tmp/container/Library/Preferences")

        makeService(pasteboard: pasteboard, exporter: exporter)
            .copyUserDefaultsJSON(fromPreferencesDirectoryAt: preferencesURL,
                                  ownDomain: "com.test.app",
                                  subject: "Test App")

        #expect(pasteboard.lastWrittenString == "{ \"key\" : 1 }")
        #expect(exporter.lastRequest == MockUserDefaultsExporter.Request(url: preferencesURL,
                                                                         ownDomain: "com.test.app"))
    }

    @Test("A failed export reports the failure and leaves the clipboard untouched")
    @MainActor
    func failedExportReportsAndDoesNotCopy() {
        let pasteboard = MockPasteboard()
        let exporter = MockUserDefaultsExporter()
        exporter.result = .failure(MockUserDefaultsExporter.MockError.exportFailed)
        let errorReporter = MockUserFacingErrorReporter()

        makeService(pasteboard: pasteboard, exporter: exporter, errorReporter: errorReporter)
            .copyUserDefaultsJSON(fromPreferencesDirectoryAt: URL(fileURLWithPath: "/tmp/container/Library/Preferences"),
                                  ownDomain: "com.test.app",
                                  subject: "Test App")

        #expect(!pasteboard.didWrite)
        #expect(errorReporter.reports.count == 1)
        #expect(errorReporter.reports.first?.title == "Could not copy UserDefaults for Test App")
        #expect(errorReporter.reports.first?.message == "Mock export failure")
    }
}
