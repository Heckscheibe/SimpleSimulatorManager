//
//  ContainerShortcutTests.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 25.08.26.
//

import Foundation
import Testing
@testable import SimulatorManager

@Suite("ContainerShortcut Tests")
struct ContainerShortcutTests {
    private static let containerURL = URL(fileURLWithPath: "/tmp/container")
    private static let bundleURL = URL(fileURLWithPath: "/tmp/bundle/Test.app")

    @Test("An app with all containers offers every shortcut")
    func fullyPopulatedAppOffersEveryShortcut() {
        let app = TestDataHelpers.createMockApp(appDocumentsFolderURL: Self.containerURL,
                                                appPackageURL: Self.bundleURL,
                                                hasUserDefaults: true)

        #expect(AppContainerShortcut.available(for: app) == [.documents, .appPackage, .userDefaults])
    }

    @Test("Shortcuts resolve to the folders the Finder actions have always opened")
    func shortcutsResolveToTheExpectedFolders() {
        let app = TestDataHelpers.createMockApp(appDocumentsFolderURL: Self.containerURL,
                                                appPackageURL: Self.bundleURL,
                                                hasUserDefaults: true)

        #expect(AppContainerShortcut.documents.url(for: app) == Self.containerURL)
        #expect(AppContainerShortcut.appPackage.url(for: app)?.path == "/tmp/bundle")
        #expect(AppContainerShortcut.userDefaults.url(for: app)
            == Self.containerURL.appendingPathComponent(SimulatorPaths.userDefaultsPath))
    }

    @Test("An app without UserDefaults is not offered the UserDefaults shortcut")
    func appWithoutUserDefaultsHidesTheShortcut() {
        let app = TestDataHelpers.createMockApp(appDocumentsFolderURL: Self.containerURL,
                                                appPackageURL: Self.bundleURL,
                                                hasUserDefaults: false)

        #expect(AppContainerShortcut.available(for: app) == [.documents, .appPackage])
    }

    @Test("Shortcuts whose URL cannot be derived are left out")
    func shortcutsWithoutURLAreLeftOut() {
        let app = TestDataHelpers.createMockApp(hasUserDefaults: true)

        #expect(AppContainerShortcut.available(for: app).isEmpty)
    }

    @Test("An app group offers its folder and, when present, its UserDefaults")
    func appGroupShortcuts() {
        let groupURL = URL(fileURLWithPath: "/tmp/group")
        let withUserDefaults = AppGroup(identifier: "group.com.test", uuid: "uuid", hasUserDefaults: true, url: groupURL)
        let withoutUserDefaults = AppGroup(identifier: "group.com.test", uuid: "uuid", hasUserDefaults: false, url: groupURL)
        let withoutURL = AppGroup(identifier: "group.com.test", uuid: "uuid", hasUserDefaults: true)

        #expect(AppGroupShortcut.available(for: withUserDefaults) == [.groupFolder, .userDefaults])
        #expect(AppGroupShortcut.available(for: withoutUserDefaults) == [.groupFolder])
        #expect(AppGroupShortcut.available(for: withoutURL).isEmpty)
        #expect(AppGroupShortcut.userDefaults.url(for: withUserDefaults)
            == groupURL.appendingPathComponent(SimulatorPaths.userDefaultsPath))
    }
}
