//
//  MenuPanelScaleTests.swift
//  SimulatorManagerTests
//
//  Created by Nicolas Hiller on 05.09.26.
//

import Foundation
import Testing
@testable import SimulatorManager

/// A machine with several Xcode versions installed carries dozens of simulators, each with its own
/// apps. The panel rebuilds its tree on every render and matches on every keystroke, so both have to
/// stay cheap at that size — and cheap is a claim worth measuring rather than asserting.
@Suite("Menu panel at scale")
@MainActor
struct MenuPanelScaleTests {
    private static let deviceCount = 45
    private static let appsPerDevice = 20

    @Test("Building the whole menu tree for a large install stays well under a frame budget")
    func treeBuildingStaysCheap() async {
        let fixture = MenuTreeFixture()
        defer { fixture.tearDown() }

        await fixture.setDevices(Self.makeDevices())
        let builder = fixture.makeBuilder()

        // Warm up, so the first run's one-off costs are not what gets measured.
        _ = builder.makeNodes()

        let clock = ContinuousClock()
        let duration = clock.measure {
            for _ in 0 ..< 10 {
                _ = builder.makeNodes()
            }
        }
        let perBuild = duration / 10

        // Generous: the point is to catch an accidental quadratic or a filesystem call sneaking in,
        // not to police milliseconds on a loaded machine.
        #expect(perBuild < .milliseconds(250))
    }

    @Test("Indexing a large install once, and then matching per keystroke, both stay cheap")
    func searchStaysCheapPerKeystroke() {
        let devices = Self.makeDevices()
        let searchService = MenuSearchService()
        let visiblePlatforms: Set<SimulatorPlatform> = [.iPhone, .iPad, .watch, .appleTV, .visionPro, .iPodTouch]
        let clock = ContinuousClock()

        let indexingDuration = clock.measure {
            searchService.updateIndex(devices: devices, recentApps: [], visiblePlatforms: visiblePlatforms)
        }

        // What the user actually types, one character at a time.
        let queries = ["a", "ap", "app", "app ", "app 1", "app 12"]
        let matchingDuration = clock.measure {
            for _ in 0 ..< 20 {
                for query in queries {
                    _ = searchService.results(for: query)
                }
            }
        }
        let perQuery = matchingDuration / (20 * queries.count)

        #expect(indexingDuration < .milliseconds(500))
        #expect(perQuery < .milliseconds(20))
    }

    @Test("Every app on every visible device is reachable through search")
    func everyAppIsIndexed() {
        let devices = Self.makeDevices()
        let searchService = MenuSearchService()
        searchService.updateIndex(devices: devices,
                                  recentApps: [],
                                  visiblePlatforms: [.iPhone, .iPad, .watch, .appleTV, .visionPro, .iPodTouch])

        // One entry per app per device, and nothing lost to a collision between same-named apps.
        let results = searchService.results(for: "com.test.app")
        let expected = Self.deviceCount * Self.appsPerDevice

        #expect(results.count == expected)
        #expect(Set(results.map(\.id)).count == expected)
    }
}

private extension MenuPanelScaleTests {
    static func makeDevices() -> [Device] {
        (0 ..< deviceCount).map { deviceIndex in
            let device = TestDataHelpers.createMockDevice(udid: "device-\(deviceIndex)",
                                                          name: "iPhone \(deviceIndex % 9)",
                                                          osVersion: "\(17 + deviceIndex % 3).\(deviceIndex % 5)")
            device.apps = (0 ..< appsPerDevice).map { appIndex in
                TestDataHelpers.createMockApp(bundleIdentifier: "com.test.app\(appIndex)",
                                              displayName: "Test App \(appIndex)")
            }

            return device
        }
    }
}
