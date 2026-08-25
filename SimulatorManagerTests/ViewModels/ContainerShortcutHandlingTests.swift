//
//  ContainerShortcutHandlingTests.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 25.08.26.
//

import Foundation
import Testing
@testable import SimulatorManager

@Suite("Container Shortcut Handling Tests")
struct ContainerShortcutHandlingTests {
    private static let containerURL = URL(fileURLWithPath: "/tmp/container")

    @MainActor
    private func makeViewModel(containerContent: MockContainerContentCopier) -> DeviceViewModel {
        DeviceViewModel(device: TestDataHelpers.createMockDevice(),
                        deviceManager: MockDeviceManager(),
                        simulatorResetService: MockSimulatorDeviceActionService(),
                        containerContent: containerContent)
    }

    @Test("Copying an app shortcut path copies the folder that shortcut opens")
    @MainActor
    func copyingAppShortcutPath() {
        let containerContent = MockContainerContentCopier()
        let app = TestDataHelpers.createMockApp(appDocumentsFolderURL: Self.containerURL,
                                                appPackageURL: URL(fileURLWithPath: "/tmp/bundle/Test.app"))

        makeViewModel(containerContent: containerContent).didSelectCopyPath(of: .appPackage, for: app)

        #expect(containerContent.lastCopiedPath?.path == "/tmp/bundle")
    }

    @Test("Copying an app's UserDefaults asks for its own preferences plist")
    @MainActor
    func copyingAppUserDefaults() {
        let containerContent = MockContainerContentCopier()
        let app = TestDataHelpers.createMockApp(bundleIdentifier: "com.test.app",
                                                displayName: "Test App",
                                                appDocumentsFolderURL: Self.containerURL,
                                                hasUserDefaults: true)

        makeViewModel(containerContent: containerContent).didSelectCopyUserDefaultsJSON(for: app)

        let expected = MockContainerContentCopier.UserDefaultsRequest(
            url: Self.containerURL.appendingPathComponent(SimulatorPaths.userDefaultsPath),
            preferredPlistName: "com.test.app",
            subject: "Test App"
        )

        #expect(containerContent.lastUserDefaultsRequest == expected)
    }

    @Test("Copying an app group's UserDefaults asks for the group's plist")
    @MainActor
    func copyingAppGroupUserDefaults() {
        let containerContent = MockContainerContentCopier()
        let groupURL = URL(fileURLWithPath: "/tmp/group")
        let appGroup = AppGroup(identifier: "group.com.test", uuid: "uuid", hasUserDefaults: true, url: groupURL)

        makeViewModel(containerContent: containerContent).didSelectCopyUserDefaultsJSON(for: appGroup)

        let expected = MockContainerContentCopier.UserDefaultsRequest(
            url: groupURL.appendingPathComponent(SimulatorPaths.userDefaultsPath),
            preferredPlistName: "group.com.test",
            subject: "Group com.test"
        )

        #expect(containerContent.lastUserDefaultsRequest == expected)
    }

    @Test("A shortcut without a resolvable URL copies nothing")
    @MainActor
    func unresolvableShortcutCopiesNothing() {
        let containerContent = MockContainerContentCopier()
        let app = TestDataHelpers.createMockApp(hasUserDefaults: true)
        let viewModel = makeViewModel(containerContent: containerContent)

        viewModel.didSelectCopyPath(of: .documents, for: app)
        viewModel.didSelectCopyUserDefaultsJSON(for: app)
        viewModel.didSelectCopyPath(of: nil)

        #expect(containerContent.copiedPaths.isEmpty)
        #expect(containerContent.userDefaultsRequests.isEmpty)
    }

    @Test("Device view models copy through the same service as the menu they came from")
    @MainActor
    func deviceViewModelsShareTheCopyingService() {
        let containerContent = MockContainerContentCopier()
        let viewModel = SimulatorManagerViewModel(deviceManager: MockDeviceManager(),
                                                  simulatorResetService: MockSimulatorDeviceActionService(),
                                                  deviceAppMonitoringService: MockDeviceAppMonitoringService(),
                                                  containerContent: containerContent)
        let deviceViewModel = viewModel.makeDeviceViewModel(for: TestDataHelpers.createMockDevice())

        deviceViewModel.didSelectCopyPath(of: Self.containerURL)

        #expect(containerContent.lastCopiedPath == Self.containerURL)
    }
}
